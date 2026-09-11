# Privacy Policy for Spender Pro

**Effective Date:** September 9, 2026  
**Last Updated:** September 9, 2026  
**Application Name:** Spender Pro  
**Package Name:** `com.budget.planning`  

---

### 1. Overview & Commitment to Privacy
Spender Pro ("the App") is committed to protecting your privacy. The App is built on a **strict 100% on-device, offline architecture**. All financial tracking, budget calculations, and notification scanning occur entirely on your local device sandbox. **No personal, financial, or transaction data is ever collected, transmitted, stored on remote servers, or shared with third parties.**

---

### 2. Information We Access and How It Is Used

#### A. Bank Payment Notifications & SMS Header Scanning
- **Access:** Spender Pro accesses status bar bank notifications and official bank notification titles (e.g., TRAI headers like `HDFCBK`, `SBICRD`, `ICICIB`).
- **Purpose:** To automatically log bank transactions, debit/credit card expenses, and compute real-time card balances.
- **Local Processing:** All notification parsing is performed 100% locally on your device in real-time. Raw notification contents are **never uploaded to external servers or cloud databases**.

#### B. Financial & Budget Data
- **Access:** User-configured card limits, warning boundaries, card names, custom category labels, and daily transaction entries.
- **Purpose:** To display card carousel metrics, analytics charts, and send system alerts when spending reaches budget limits.
- **Encryption:** All stored expense data and card configurations are encrypted locally using **AES-256 encryption** before being saved to private local device storage.

#### C. System Permissions Used
- **`BIND_NOTIFICATION_LISTENER_SERVICE`**: Required to listen to incoming status bar bank notifications for real-time payment logging.
- **`POST_NOTIFICATIONS`**: Required to show local system notification alerts when spending reaches your warning boundary or maximum budget limit.

---

### 3. Data Storage and Retention
- **Local Storage Only:** All application data is stored in the private application directory on your device.
- **User Control & Deletion:** You can clear all data at any time by uninstalling the App or clearing App Storage/Cache in Android System Settings. Once deleted, data cannot be recovered as no cloud backups exist.

---

### 4. Third-Party Services and Analytics
Spender Pro **does not contain any third-party SDKs, tracking pixels, advertising networks, or remote analytics tools** (such as Firebase Analytics, Google Analytics, or advertising SDKs) that collect or track user activity.

---

### 5. Children's Privacy
Spender Pro is designed for general audiences and does not knowingly collect any data from children under the age of 13.

---

### 6. Security
We prioritize the security of your data. Because all processing is local and protected by AES-256 encryption within the Android OS app sandbox, your financial data remains safe from external unauthorized interception.

---

### 7. Changes to This Privacy Policy
We may update our Privacy Policy from time to time. Any updates will be reflected in this document with a revised "Last Updated" date.

---

### 8. Contact Us
If you have any questions or feedback regarding this Privacy Policy or Spender Pro's privacy practices, please contact us at:
- **Email:** support@spenderpro.app
