package com.budget.planning

import android.app.Notification
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

class BankNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "BankNotifListener"
        const val ACTION_NOTIFICATION_RECEIVED = "com.budget.planning.NOTIFICATION_RECEIVED"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_TEXT = "extra_text"
        const val EXTRA_PACKAGE = "extra_package"
        const val EXTRA_TIMESTAMP = "extra_timestamp"

        private const val ENCRYPTION_KEY = "WidgetLearningAppKey_1234567890!"
        private const val ENCRYPTION_IV = "WidgetIV_1234567"

        @Volatile
        var isConnected = false

        @Volatile
        var instance: BankNotificationListenerService? = null
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnected = true
        instance = this
        Log.d(TAG, "BankNotificationListenerService connected to Android Notification System!")
        scanActiveNotifications()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isConnected = false
        instance = null
        Log.w(TAG, "BankNotificationListenerService disconnected from Android Notification System! Attempting rebind...")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                requestRebind(ComponentName(this, BankNotificationListenerService::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "Failed to requestRebind on disconnect", e)
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return
        processStatusBarNotification(sbn)
    }

    fun scanActiveNotifications() {
        try {
            val activeNotifs = activeNotifications ?: return
            Log.d(TAG, "Scanning ${activeNotifs.size} active status bar notifications...")
            for (sbn in activeNotifs) {
                processStatusBarNotification(sbn)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error scanning active notifications", e)
        }
    }

    private fun processStatusBarNotification(sbn: StatusBarNotification) {
        try {
            val packageName = sbn.packageName ?: ""
            if (packageName == applicationContext.packageName) return

            val extras = sbn.notification?.extras ?: return
            var defaultTitle = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val titleBig = extras.getCharSequence(Notification.EXTRA_TITLE_BIG)?.toString() ?: ""
            if (defaultTitle.isEmpty() && titleBig.isNotEmpty()) {
                defaultTitle = titleBig
            }

            var processedAnyIndividualMessage = false

            // 1. Process individual Notification.MessagingStyle messages
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    val rawMessages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
                    if (rawMessages != null && rawMessages.isNotEmpty()) {
                        for (msg in rawMessages) {
                            var msgText = ""
                            var msgSender = defaultTitle
                            var msgTimestamp = sbn.postTime

                            if (msg is Bundle) {
                                msgText = msg.getCharSequence("text")?.toString() ?: ""
                                val senderStr = msg.getCharSequence("sender")?.toString() ?: ""
                                if (senderStr.isNotEmpty()) msgSender = senderStr
                                val ts = msg.getLong("time", 0L)
                                if (ts > 0L) msgTimestamp = ts
                            } else if (msg is Notification.MessagingStyle.Message) {
                                msgText = msg.text?.toString() ?: ""
                                val senderStr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    msg.senderPerson?.name?.toString() ?: msg.sender?.toString() ?: ""
                                } else {
                                    msg.sender?.toString() ?: ""
                                }
                                if (senderStr.isNotEmpty()) msgSender = senderStr
                                val ts = msg.timestamp
                                if (ts > 0L) msgTimestamp = ts
                            }

                            if (msgText.isNotEmpty() && isPaymentAlert(msgSender, msgText)) {
                                saveToNotificationCacheQueue(msgSender, msgText, packageName, msgTimestamp)
                                try { processAndSaveBackgroundTransaction(msgSender, msgText, msgTimestamp) } catch (e: Exception) { Log.e(TAG, "Error in processAndSaveBackgroundTransaction", e) }
                                broadcastNotification(msgSender, msgText, packageName, msgTimestamp)
                                processedAnyIndividualMessage = true
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error parsing MessagingStyle", e)
                }
            }

            // 2. Process individual InboxStyle text lines
            val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            if (lines != null && lines.isNotEmpty()) {
                for (line in lines) {
                    val lineStr = line?.toString() ?: ""
                    if (lineStr.isNotEmpty() && isPaymentAlert(defaultTitle, lineStr)) {
                        saveToNotificationCacheQueue(defaultTitle, lineStr, packageName, sbn.postTime)
                        try { processAndSaveBackgroundTransaction(defaultTitle, lineStr, sbn.postTime) } catch (e: Exception) { Log.e(TAG, "Error in processAndSaveBackgroundTransaction", e) }
                        broadcastNotification(defaultTitle, lineStr, packageName, sbn.postTime)
                        processedAnyIndividualMessage = true
                    }
                }
            }

            // 3. Fallback: Process standard single notification if no individual messages were processed
            if (!processedAnyIndividualMessage) {
                val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
                val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
                val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
                val summaryText = extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString() ?: ""

                val combinedBody = "$text $bigText $subText $summaryText".trim()
                if ((defaultTitle.isNotEmpty() || combinedBody.isNotEmpty()) &&
                    isPaymentAlert(defaultTitle, combinedBody)) {
                    saveToNotificationCacheQueue(defaultTitle, combinedBody, packageName, sbn.postTime)
                    try { processAndSaveBackgroundTransaction(defaultTitle, combinedBody, sbn.postTime) } catch (e: Exception) { Log.e(TAG, "Error in processAndSaveBackgroundTransaction", e) }
                    broadcastNotification(defaultTitle, combinedBody, packageName, sbn.postTime)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing status bar notification", e)
        }
    }

    private fun broadcastNotification(title: String, text: String, packageName: String, timestamp: Long) {
        try {
            val intent = Intent(ACTION_NOTIFICATION_RECEIVED).apply {
                setPackage(applicationContext.packageName)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
                putExtra(EXTRA_PACKAGE, packageName)
                putExtra(EXTRA_TIMESTAMP, timestamp)
            }
            sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error broadcasting notification", e)
        }
    }

    private fun isOfficialBankSenderTitle(title: String): Boolean {
        val clean = title.trim().uppercase(Locale.ROOT)
        if (clean.isEmpty() || clean.length > 35) return false
        val blockedWords = arrayOf(
            "SYSTEM", "NOTIFICATION", "MESSAGES", "ALERT", "AIRTEL", "JIO",
            "VODAFONE", "IDEA", "BSNL", "ACT", "SWIGGY", "ZOMATO", "AMAZON",
            "FLIPKART", "MYNTRA", "UBER", "OLA", "DOMINOS", "MEESHO", "NYKAA",
            "VAAHAN", "SARATHI", "PARIVAHAN", "ECHALLAN", "WLPARK", "WONDERLA",
            "MYGMSG", "MYG", "UIICHO", "UIIC", "PHONPE", "PHONEPE", "GPAY",
            "MOBIKW", "FREECH", "PAYTM", "IRCTC", "MAKEMY", "GOIBIB", "YATRA",
            "REDBUS", "BOOKMY", "PVR", "INOX", "CROMA", "VIJAYS", "RELIAN", "DMART"
        )
        for (b in blockedWords) {
            if (clean.contains(b)) return false
        }
        return true
    }

    private fun isPaymentAlert(title: String, fullText: String): Boolean {
        if (!isOfficialBankSenderTitle(title)) return false

        val lower = fullText.lowercase(Locale.ROOT)

        // Reject balance stands / bal after txn summary messages
        if (lower.contains("bal stands") || lower.contains("bal standsrs") || lower.contains("balance stands") || lower.contains("bal stands rs") ||
            lower.contains("bal after txn") || lower.contains("bal after transaction") || lower.contains("balance after txn") || lower.contains("balance after transaction") ||
            lower.contains("avail bal") || lower.contains("available bal") || lower.contains("available balance") ||
            lower.contains("after debit of") || lower.contains("after credit of")) {
            return false
        }

        // Reject promotional ad, loan offer, marketing & reward notifications
        val promoKeywords = arrayOf(
            "loan", "pre-approved", "pre approved", "apply now", "avail", "offer", "offers",
            "congratulations", "congrats", "reward", "rewards", "cashback of up to", "win up to",
            "earn up to", "t&c apply", "t&c", "check emi options", "zero documentation",
            "zero stamp duty", "lowest rates", "get cash", "badhti", "mutual fund", "investment",
            "discount", "promo", "promotional", "limited period", "claim now", "click here", "eligible for"
        )
        for (kw in promoKeywords) {
            if (lower.contains(kw)) return false
        }

        // Reject bill due, statement generated, and credit limit notices unless explicit transaction is present
        if (lower.contains("bill due") || lower.contains("payment due") ||
            lower.contains("statement generated") || lower.contains("e-statement") ||
            lower.contains("credit limit") || lower.contains("minimum amount due") ||
            lower.contains("total amount due")) {
            if (!lower.contains("debited") && !lower.contains("credited") &&
                !lower.contains("spent") && !lower.contains("spend") &&
                !lower.contains("has been paid") && !lower.contains("paid rs") &&
                !lower.contains("paid inr") && !lower.contains("paid ₹")) {
                return false
            }
        }

        // Reject OTP / verification codes unless there is an explicit debit/credit confirmation
        if (lower.contains("otp") || lower.contains("one time password") ||
            lower.contains("verification code") || lower.contains("secret code") ||
            lower.contains("login code") || lower.contains("auth code")) {
            if (!lower.contains("has been debited") && !lower.contains("is debited") &&
                !lower.contains("has been credited") && !lower.contains("is credited")) {
                return false
            }
        }

        // Mandatory transaction action verbs (credited, debited, spent, spend, paid to/you, withdrawn, etc.)
        val isExplicitAction = lower.contains("credited") ||
                lower.contains("debited") ||
                lower.contains("spent") ||
                lower.contains("spend") ||
                lower.contains("paid to") ||
                lower.contains("paid you") ||
                lower.contains("withdrawn") ||
                lower.contains("refund") ||
                lower.contains("refunded") ||
                lower.contains("deposited") ||
                lower.contains("deducted") ||
                lower.contains("transferred to") ||
                lower.contains("received rs") ||
                lower.contains("received inr") ||
                lower.contains("received ₹")

        if (isExplicitAction) return true

        // For 'credit' or 'debit', ensure it's not a generic reference to 'credit card' or 'debit card'
        if ((lower.contains("debit") || lower.contains("credit")) &&
            !lower.contains("credit card") && !lower.contains("debit card") &&
            !lower.contains("credit limit") && !lower.contains("dispatched")) {
            return true
        }

        return false
    }

    private fun saveToNotificationCacheQueue(title: String, body: String, packageName: String, timestamp: Long) {
        try {
            val fullText = "$title $body"
            if (!isPaymentAlert(title, fullText)) return

            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val rawCache = prefs.getString("flutter.pending_notification_cache", "[]") ?: "[]"

            val cacheArray = try {
                JSONArray(rawCache)
            } catch (e: Exception) {
                JSONArray()
            }

            // Check if identical item (title + body) already exists in cache within 5 seconds to prevent duplicate queue items
            var isDuplicate = false
            for (i in 0 until cacheArray.length()) {
                val existing = cacheArray.optJSONObject(i) ?: continue
                val existingTitle = existing.optString("title", "")
                val existingText = existing.optString("text", "")
                val existingTs = existing.optLong("timestamp", 0L)
                if (existingTitle == title && existingText == body && Math.abs(existingTs - timestamp) < 5000) {
                    isDuplicate = true
                    break
                }
            }

            if (!isDuplicate) {
                val item = JSONObject().apply {
                    put("id", timestamp.toString())
                    put("title", title)
                    put("text", body)
                    put("packageName", packageName)
                    put("timestamp", timestamp)
                }

                cacheArray.put(item)
                prefs.edit().putString("flutter.pending_notification_cache", cacheArray.toString()).apply()
                Log.d(TAG, "Added notification to pending background cache queue. Size: ${cacheArray.length()}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error saving to pending notification cache queue", e)
        }
    }

    private fun processAndSaveBackgroundTransaction(title: String, body: String, timestamp: Long) {
        try {
            val fullText = "$title $body"
            if (!isPaymentAlert(title, fullText)) return

            // Extract amount
            val amount = parseAmount(fullText) ?: return

            // Extract type
            val isCredit = fullText.contains("credited", ignoreCase = true) ||
                    fullText.contains("received", ignoreCase = true) ||
                    fullText.contains("paid you", ignoreCase = true)
            val type = if (isCredit) "credited" else "spent"

            // Extract bank / merchant name
            val bankName = extractBankName(title, body)
            Log.d(TAG, "Parsed Background Notification -> Bank: $bankName, Amount: ${parseAmount(fullText)}")

            // Access FlutterSharedPreferences (read-only for updating HomeWidget)
            val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            updateHomeWidgetNatively(prefs, bankName)

        } catch (e: Exception) {
            Log.e(TAG, "Error updating background transaction status", e)
        }
    }

    private fun parseAmount(text: String): Double? {
        // Match patterns like "Rs. 1.00", "INR 1", "₹1.00", "paid you ₹1.00"
        val regex1 = Regex("""(?i)(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d+)?)""")
        val match1 = regex1.find(text)
        if (match1 != null) {
            val amtStr = match1.groupValues[1].replace(",", "")
            return amtStr.toDoubleOrNull()
        }

        val regex2 = Regex("""(?i)(?:paid\s+you|sent\s+you|credited\s+with|credited\s+by|debited\s+for|spent)\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d+)?)""")
        val match2 = regex2.find(text)
        if (match2 != null) {
            val amtStr = match2.groupValues[1].replace(",", "")
            return amtStr.toDoubleOrNull()
        }

        return null
    }

    private fun extractBankName(title: String, body: String): String {
        val cleanTitle = title.trim()
        if (cleanTitle.isEmpty()) return "BANK"

        // 1. Check TRAI header format: 2-letter operator prefix followed by hyphen (e.g. AD-KGBANK-S -> KGBANK-S, JX-HDFCBK-T -> HDFCBK-T)
        val parts = cleanTitle.split("-")
        if (parts.size >= 2 && parts[0].length == 2 && Regex("""^[A-Za-z]{2}$""").matches(parts[0])) {
            val bankPart = parts.subList(1, parts.size).joinToString("-").uppercase(Locale.ROOT)
            if (bankPart.isNotEmpty()) {
                if (bankPart.endsWith("-S") || bankPart.endsWith("-T")) {
                    return bankPart
                }
                return "$bankPart-S"
            }
        }

        val upper = cleanTitle.uppercase(Locale.ROOT)
        if (upper.endsWith("-S") || upper.endsWith("-T")) {
            return upper
        }
        return "$upper-S"
    }

    private fun extractMerchantName(title: String, body: String): String {
        val paidYouRegex = Regex("""(?i)([a-zA-Z0-9\s._]+)\s+paid\s+you""")
        val paidMatch = paidYouRegex.find("$title $body")
        if (paidMatch != null) {
            val name = paidMatch.groupValues[1].trim()
            if (name.isNotEmpty()) return name
        }

        val fromRegex = Regex("""(?i)from\s+([a-zA-Z0-9._@]+)""")
        val fromMatch = fromRegex.find(body)
        if (fromMatch != null) {
            val name = fromMatch.groupValues[1].trim()
            if (name.isNotEmpty()) return name
        }

        if (title.isNotEmpty() && !title.contains("-")) {
            return title.trim()
        }

        return "Bank Alert"
    }

    private fun updateHomeWidgetNatively(prefs: android.content.SharedPreferences, targetBank: String) {
        try {
            val activeCard = prefs.getString("flutter.cardName", "")?.ifEmpty { targetBank } ?: targetBank
            val encryptedExpenses = prefs.getString("flutter.local_expenses", "") ?: ""

            if (encryptedExpenses.isEmpty()) return

            val decryptedJson = decryptData(encryptedExpenses)
            val expensesArray = try {
                JSONArray(decryptedJson)
            } catch (_: Exception) {
                return
            }

            val calendar = Calendar.getInstance()
            val currentMonth = calendar.get(Calendar.MONTH) + 1
            val currentYear = calendar.get(Calendar.YEAR)

            var totalSpent = 0.0
            for (i in 0 until expensesArray.length()) {
                val item = expensesArray.optJSONObject(i) ?: continue
                val bank = item.optString("bank", "")
                val type = item.optString("type", "spent")
                val amount = item.optDouble("amount", 0.0)
                val dateMs = item.optLong("date", 0L)

                val itemCal = Calendar.getInstance().apply { timeInMillis = dateMs }
                val itemMonth = itemCal.get(Calendar.MONTH) + 1
                val itemYear = itemCal.get(Calendar.YEAR)

                if (itemMonth == currentMonth && itemYear == currentYear &&
                    (type == "spent" || type == "debited") &&
                    (bank.contains(activeCard, ignoreCase = true) || activeCard.contains(bank, ignoreCase = true))
                ) {
                    totalSpent += amount
                }
            }

            val limitKey = "flutter.limit_$activeCard"
            val boundaryKey = "flutter.boundary_$activeCard"

            val limit = prefs.getFloat(limitKey, 80000f).toDouble()
            val boundary = prefs.getFloat(boundaryKey, 0f).toDouble()

            val hasBoundary = boundary > 0
            val effectiveLimit = if (hasBoundary) boundary else limit
            val remaining = effectiveLimit - totalSpent
            val progress = if (limit > 0) ((totalSpent / limit) * 100).toInt() else 0
            val isWarning = hasBoundary && totalSpent >= boundary

            val monthFormat = SimpleDateFormat("MMM", Locale.US)
            val monthName = monthFormat.format(Date()).uppercase(Locale.ROOT)
            val displayCardName = if (isWarning) "$activeCard ⚠️" else activeCard

            // Save to HomeWidgetPreferences for HomeWidget plugin
            val widgetPrefs = applicationContext.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            widgetPrefs.edit().apply {
                putString("current_value", String.format(Locale.US, "%.0f", totalSpent))
                putString("max_value", String.format(Locale.US, "%.0f", limit))
                putString("boundary_value", String.format(Locale.US, "%.0f", boundary))
                putBoolean("has_boundary", hasBoundary)
                putString("remaining_budget", String.format(Locale.US, "%.0f", remaining))
                putInt("progress", progress)
                putString("month_name", monthName)
                putString("card_name", displayCardName)
                putBoolean("is_warning", isWarning)
                apply()
            }

            // Trigger widget refresh across all widget instances natively
            val appWidgetManager = AppWidgetManager.getInstance(applicationContext)

            val mainComponent = ComponentName(applicationContext, NagavalliWidgetProvider::class.java)
            val mainIds = appWidgetManager.getAppWidgetIds(mainComponent)
            if (mainIds.isNotEmpty()) {
                NagavalliWidgetProvider().onUpdate(applicationContext, appWidgetManager, mainIds)
            }

            val pieComponent = ComponentName(applicationContext, NagavalliPieWidgetProvider::class.java)
            val pieIds = appWidgetManager.getAppWidgetIds(pieComponent)
            if (pieIds.isNotEmpty()) {
                NagavalliPieWidgetProvider().onUpdate(applicationContext, appWidgetManager, pieIds)
            }

            val lineComponent = ComponentName(applicationContext, NagavalliLineWidgetProvider::class.java)
            val lineIds = appWidgetManager.getAppWidgetIds(lineComponent)
            if (lineIds.isNotEmpty()) {
                NagavalliLineWidgetProvider().onUpdate(applicationContext, appWidgetManager, lineIds)
            }

            Log.d(TAG, "Successfully updated HomeWidget natively! Card: $displayCardName, Total: $totalSpent")
        } catch (e: Exception) {
            Log.e(TAG, "Error updating HomeWidget natively", e)
        }
    }

    private fun decryptData(encryptedBase64: String): String {
        if (encryptedBase64.isEmpty()) return encryptedBase64
        return try {
            val keyBytes = ENCRYPTION_KEY.toByteArray(Charsets.UTF_8)
            val ivBytes = ENCRYPTION_IV.toByteArray(Charsets.UTF_8)
            val secretKey = SecretKeySpec(keyBytes, "AES")
            val ivSpec = IvParameterSpec(ivBytes)
            val cipher = Cipher.getInstance("AES/CBC/PKCS7Padding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey, ivSpec)
            val decodedBytes = Base64.decode(encryptedBase64, Base64.DEFAULT)
            String(cipher.doFinal(decodedBytes), Charsets.UTF_8)
        } catch (e: Exception) {
            encryptedBase64
        }
    }

    private fun encryptData(plainText: String): String {
        if (plainText.isEmpty()) return plainText
        return try {
            val keyBytes = ENCRYPTION_KEY.toByteArray(Charsets.UTF_8)
            val ivBytes = ENCRYPTION_IV.toByteArray(Charsets.UTF_8)
            val secretKey = SecretKeySpec(keyBytes, "AES")
            val ivSpec = IvParameterSpec(ivBytes)
            val cipher = Cipher.getInstance("AES/CBC/PKCS7Padding")
            cipher.init(Cipher.ENCRYPT_MODE, secretKey, ivSpec)
            val encryptedBytes = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
            Base64.encodeToString(encryptedBytes, Base64.NO_WRAP)
        } catch (e: Exception) {
            plainText
        }
    }
}
