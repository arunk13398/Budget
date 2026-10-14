package com.budget.planning

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import java.io.File
import java.text.NumberFormat
import java.util.Locale

class NagavalliWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        Log.d("NagavalliWidget", "Updating card widget. Data: ${widgetData.all}")

        for (appWidgetId in appWidgetIds) {
            updateWidgetInstance(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        Log.d("NagavalliWidget", "Widget resized: options changed for ID $appWidgetId")
        updateWidgetInstance(context, appWidgetManager, appWidgetId)
    }

    private fun updateWidgetInstance(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        try {
            val widgetData = HomeWidgetPlugin.getData(context)
            val numberFormat = NumberFormat.getInstance(Locale("en", "IN"))
            val views = RemoteViews(context.packageName, R.layout.home_widget)
            
            val currentValueStr = widgetData.getString("current_value", "0") ?: "0"
            val maxValueStr = widgetData.getString("max_value", "0") ?: "0"
            val boundaryValueStr = widgetData.getString("boundary_value", "0") ?: "0"
            val remainingBudgetStr = widgetData.getString("remaining_budget", "0") ?: "0"
            val progress = widgetData.getInt("progress", 0)
            val monthName = widgetData.getString("month_name", "---") ?: "---"
            val cardName = widgetData.getString("card_name", "Budget") ?: "Budget"
            val isWarning = widgetData.getBoolean("is_warning", false)
            
            val valDouble = currentValueStr.toDoubleOrNull() ?: 0.0
            val limitDouble = maxValueStr.toDoubleOrNull() ?: 0.0
            var boundaryDouble = boundaryValueStr.toDoubleOrNull() ?: 0.0

            // Robust fallback to FlutterSharedPreferences if boundary_value was not yet stored in HomeWidgetPreferences
            if (boundaryDouble <= 0.0) {
                val cleanCard = cardName.replace(" ⚠️", "").trim()
                try {
                    val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val fVal = flutterPrefs.getFloat("flutter.boundary_$cleanCard", 0f).toDouble()
                    if (fVal > 0.0) boundaryDouble = fVal
                } catch (_: Exception) {}
            }

            val hasBoundary = boundaryDouble > 0.0
            val remainingDouble = if (hasBoundary) {
                boundaryDouble - valDouble
            } else {
                remainingBudgetStr.toDoubleOrNull() ?: (limitDouble - valDouble)
            }

            val pct = if (limitDouble > 0) {
                ((valDouble / limitDouble) * 100).toInt()
            } else {
                progress
            }

            // Format numbers with commas (e.g. ₹6,853, ₹21,000, ₹14,573)
            val formattedSpent = "₹" + formatCurrency(valDouble, numberFormat)
            val formattedLimit = "₹" + formatCurrency(limitDouble, numberFormat)
            val formattedBoundary = "₹" + formatCurrency(boundaryDouble, numberFormat)
            val formattedRemaining = if (remainingDouble < 0) {
                "-₹" + formatCurrency(-remainingDouble, numberFormat)
            } else {
                "₹" + formatCurrency(remainingDouble, numberFormat)
            }

            // Header
            views.setTextViewText(R.id.tv_card_name, cardName)
            views.setTextViewText(R.id.tv_month_name, monthName.uppercase())

            // Gauge Center Content (for accessibility and fallback)
            views.setTextViewText(R.id.tv_progress_pct, "$pct%")
            views.setTextViewText(R.id.tv_spend_subtitle, "TOTAL SPEND")
            views.setTextViewText(R.id.tv_current_value, formattedSpent)

            // Bottom Metrics:
            // When boundary is added to the card, replace LIMIT section with BOUNDARY and show boundary limit value
            if (hasBoundary) {
                views.setTextViewText(R.id.tv_limit_title, "BOUNDARY")
                views.setTextViewText(R.id.tv_max_value, formattedBoundary)
            } else {
                views.setTextViewText(R.id.tv_limit_title, "LIMIT")
                views.setTextViewText(R.id.tv_max_value, formattedLimit)
            }
            views.setTextViewText(R.id.tv_remaining_budget, formattedRemaining)

            // Dynamic Styling based on budget & boundary logic
            val isExceeded = remainingDouble < 0 || (hasBoundary && valDouble >= boundaryDouble) || (limitDouble > 0 && valDouble >= limitDouble) || isWarning
            if (isExceeded) {
                views.setTextColor(R.id.tv_current_value, Color.parseColor("#E11D48"))
                views.setTextColor(R.id.tv_remaining_budget, Color.parseColor("#DC2626"))
            } else {
                views.setTextColor(R.id.tv_current_value, Color.parseColor("#0B132B"))
                views.setTextColor(R.id.tv_remaining_budget, Color.parseColor("#10B981"))
            }

            // Render dynamic curved arc gauge (Arc + Boundary Indicator + Thumb + Total Spend Hero)
            views.setViewVisibility(R.id.iv_gauge, android.view.View.VISIBLE)
            val gaugeBitmap = createArcGaugeBitmap(
                context, pct, isWarning, valDouble, limitDouble, remainingDouble, boundaryDouble, formattedSpent
            )
            views.setImageViewBitmap(R.id.iv_gauge, gaugeBitmap)
            
            // Click handlers
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, android.net.Uri.parse("homeWidget://open")
            )
            views.setOnClickPendingIntent(android.R.id.background, pendingIntent)
            
            val syncIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context, android.net.Uri.parse("homeWidget://sync")
            )
            views.setOnClickPendingIntent(R.id.btn_sync, syncIntent)
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Exception) {
            Log.e("NagavalliWidget", "Error updating card widget", e)
        }
    }

    private fun createArcGaugeBitmap(
        context: Context,
        pct: Int,
        isWarning: Boolean,
        valDouble: Double,
        limitDouble: Double,
        remainingDouble: Double,
        boundaryDouble: Double,
        formattedSpent: String
    ): Bitmap {
        val displayMetrics = context.resources.displayMetrics
        val displayDensity = displayMetrics.density
        
        // Exact proportioned canvas (240dp x 150dp) kept safely under Binder IPC limit (~500KB)
        val width = (240 * displayDensity).toInt().coerceIn(360, 480)
        val height = (150 * displayDensity).toInt().coerceIn(225, 300)
        val density = width / 240f
        
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        
        // Wide, expansive arc with exact stroke thickness matching Image 2 (~26dp)
        val strokeWidth = 26f * density
        val paddingH = strokeWidth / 2f + 6f * density
        
        val radius = (width - paddingH * 2) / 2f
        val cx = width / 2f
        val cy = height - strokeWidth / 2f - 14f * density
        
        val arcBounds = RectF(cx - radius, cy - radius, cx + radius, cy + radius)
        
        // 1. Draw Background Track Arc (Soft neutral grey #EEF2F6 with rounded caps)
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
            strokeCap = Paint.Cap.ROUND
            color = Color.parseColor("#EEF2F6")
        }
        canvas.drawArc(arcBounds, 180f, 180f, false, bgPaint)
        
        val hasBoundary = boundaryDouble > 0.0 && limitDouble > 0.0
        val isExceeded = remainingDouble < 0 || (hasBoundary && valDouble >= boundaryDouble) || (limitDouble > 0 && valDouble >= limitDouble) || isWarning
        
        // 2. Premium Theme Colors:
        val (startColor, endColor, thumbColor) = when {
            isExceeded -> {
                Triple(
                    Color.parseColor("#EF4444"), // Crimson Red
                    Color.parseColor("#F97316"), // Coral-Orange
                    Color.parseColor("#EF4444")  // Crimson Thumb
                )
            }
            else -> {
                // Signature Reference UI Design: Electric Blue to Radiant Cyan with Emerald Green Thumb!
                Triple(
                    Color.parseColor("#0062FF"), // Electric Blue
                    Color.parseColor("#00D2FF"), // Radiant Cyan
                    Color.parseColor("#10B981")  // Emerald Green Thumb
                )
            }
        }
        
        // 3. Draw Progress Arc
        val clampedProgress = pct.coerceIn(0, 100)
        val sweepAngle = 180f * (clampedProgress / 100f)
        if (clampedProgress > 0) {
            val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                this.strokeWidth = strokeWidth
                strokeCap = Paint.Cap.ROUND
                shader = LinearGradient(
                    arcBounds.left, arcBounds.top,
                    arcBounds.right, arcBounds.top,
                    startColor, endColor,
                    Shader.TileMode.CLAMP
                )
            }
            canvas.drawArc(arcBounds, 180f, sweepAngle, false, progressPaint)
        }
        
        // 4. Indicate Boundary on the Graph (if boundary is set on the card)
        if (hasBoundary) {
            val boundaryRatio = (boundaryDouble / limitDouble).toFloat().coerceIn(0.01f, 1f)
            val boundaryAngle = 180f + 180f * boundaryRatio
            val bRad = Math.toRadians(boundaryAngle.toDouble())
            val cosB = Math.cos(bRad).toFloat()
            val sinB = Math.sin(bRad).toFloat()
            
            // Boundary tick coordinates cutting across the arc track
            val innerR = radius - strokeWidth / 2f - 1.5f * density
            val outerR = radius + strokeWidth / 2f + 1.5f * density
            val bx1 = cx + innerR * cosB
            val by1 = cy + innerR * sinB
            val bx2 = cx + outerR * cosB
            val by2 = cy + outerR * sinB
            
            val markerColor = if (isExceeded) {
                Color.parseColor("#EF4444") // Alert Red when boundary exceeded
            } else {
                Color.parseColor("#F59E0B") // Amber threshold indicator
            }
            
            // White backing line for contrast against track and progress gradient
            val bBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                this.strokeWidth = 5f * density
                strokeCap = Paint.Cap.ROUND
                style = Paint.Style.STROKE
                setShadowLayer(2.5f * density, 0f, 1f * density, Color.parseColor("#40000000"))
            }
            canvas.drawLine(bx1, by1, bx2, by2, bBgPaint)
            
            // Crisp colored marker tick
            val bLinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = markerColor
                this.strokeWidth = 2.5f * density
                strokeCap = Paint.Cap.ROUND
                style = Paint.Style.STROKE
            }
            canvas.drawLine(bx1, by1, bx2, by2, bLinePaint)
            
            // Elegant indicator pin / pip at the outer rim of the track
            val pinR = outerR + 2.5f * density
            val pinX = cx + pinR * cosB
            val pinY = cy + pinR * sinB
            
            val pinHaloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                style = Paint.Style.FILL
                setShadowLayer(2f * density, 0f, 1f * density, Color.parseColor("#33000000"))
            }
            canvas.drawCircle(pinX, pinY, 4f * density, pinHaloPaint)
            
            val pinPipPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = markerColor
                style = Paint.Style.FILL
            }
            canvas.drawCircle(pinX, pinY, 2.5f * density, pinPipPaint)
        }

        // 5. Draw Pill Thumb Slider Handle (capping the tip of the progress track)
        if (clampedProgress > 0) {
            val angleRad = Math.toRadians((180f + sweepAngle).toDouble())
            val tx = cx + radius * Math.cos(angleRad).toFloat()
            val ty = cy + radius * Math.sin(angleRad).toFloat()
            
            canvas.save()
            canvas.translate(tx, ty)
            canvas.rotate((180f + sweepAngle))
            
            val pillHalfRadial = 14.5f * density  // Spans across the 26dp track
            val pillHalfTangential = 6f * density // 12dp thickness along curve
            
            // Outer white capsule border with elevation shadow
            val outerPill = RectF(
                -pillHalfRadial - 2.5f * density,
                -pillHalfTangential - 2.5f * density,
                pillHalfRadial + 2.5f * density,
                pillHalfTangential + 2.5f * density
            )
            val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                style = Paint.Style.FILL
                setShadowLayer(3.5f * density, 0f, 1f * density, Color.parseColor("#33000000"))
            }
            canvas.drawRoundRect(outerPill, 7f * density, 7f * density, borderPaint)
            
            // Inner colored capsule
            val innerPill = RectF(-pillHalfRadial, -pillHalfTangential, pillHalfRadial, pillHalfTangential)
            val thumbPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = thumbColor
                style = Paint.Style.FILL
            }
            canvas.drawRoundRect(innerPill, 5f * density, 5f * density, thumbPaint)
            
            canvas.restore()
        }
        
        // 6. Hero Texts Centered Inside the Hollow (Decongested & Bottom-Aligned with Curve Bar)
        // C. Spent Amount: Hero Amount bottom-aligned with the curve bar endpoints
        val spentColor = when {
            isExceeded -> Color.parseColor("#E11D48") // Alert Red when exceeded / warning
            (hasBoundary && valDouble >= boundaryDouble * 0.85) || (limitDouble > 0 && valDouble >= limitDouble * 0.85) -> Color.parseColor("#F59E0B") // Amber approaching limit
            else -> Color.parseColor("#0B132B") // Sleek Dark Navy for normal spend
        }
        val spentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = spentColor
            textSize = 27f * density
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        val spentY = cy + 2.5f * density // Aligned with the bottom of the curve bar

        // B. Subtitle: "TOTAL SPEND" (Bold, Slate Grey #64748B, Letter Spaced, ample breathing room)
        val subtitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#64748B")
            textSize = 9.5f * density
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            letterSpacing = 0.08f
            textAlign = Paint.Align.CENTER
        }
        val subtitleY = spentY - 29f * density

        // A. Percentage: e.g. "17%" (Bold, Dark Navy #0B132B, comfortable spacing above subtitle)
        val pctPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0B132B")
            textSize = 24f * density
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        val pctY = subtitleY - 22f * density

        canvas.drawText("$pct%", cx, pctY, pctPaint)
        canvas.drawText("TOTAL SPEND", cx, subtitleY, subtitlePaint)
        canvas.drawText(formattedSpent, cx, spentY, spentPaint)
        
        return bitmap
    }

    private fun formatCurrency(amount: Double, formatter: NumberFormat): String {
        return try {
            formatter.format(amount.toLong())
        } catch (e: Exception) {
            amount.toInt().toString()
        }
    }
}

class NagavalliPieWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val widgetData = HomeWidgetPlugin.getData(context)
        Log.d("NagavalliWidget", "Updating pie widget")
        for (appWidgetId in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, R.layout.pie_widget)
                val chartPath = widgetData.getString("pie_chart_path", null)
                
                if (chartPath != null) {
                    val file = File(chartPath)
                    if (file.exists()) {
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        views.setImageViewBitmap(R.id.iv_pie_chart, bitmap)
                    }
                }
                
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, android.net.Uri.parse("homeWidget://open"))
                views.setOnClickPendingIntent(android.R.id.background, pendingIntent)
                
                val syncIntent = HomeWidgetBackgroundIntent.getBroadcast(context, android.net.Uri.parse("homeWidget://sync"))
                views.setOnClickPendingIntent(R.id.btn_sync, syncIntent)
                
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e("NagavalliWidget", "Error updating pie widget", e)
            }
        }
    }
}

class NagavalliLineWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val widgetData = HomeWidgetPlugin.getData(context)
        Log.d("NagavalliWidget", "Updating line widget")
        for (appWidgetId in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, R.layout.line_widget)
                val chartPath = widgetData.getString("line_chart_path", null)
                
                if (chartPath != null) {
                    val file = File(chartPath)
                    if (file.exists()) {
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        views.setImageViewBitmap(R.id.iv_line_chart, bitmap)
                    }
                }
                
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, android.net.Uri.parse("homeWidget://open"))
                views.setOnClickPendingIntent(android.R.id.background, pendingIntent)
                
                val syncIntent = HomeWidgetBackgroundIntent.getBroadcast(context, android.net.Uri.parse("homeWidget://sync"))
                views.setOnClickPendingIntent(R.id.btn_sync, syncIntent)
                
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e("NagavalliWidget", "Error updating line widget", e)
            }
        }
    }
}
