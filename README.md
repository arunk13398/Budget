# Spender Pro

A modern, offline-first personal expense tracking and budgeting application built with Flutter.

---

## 🏗️ Build Flavors & Variants

Spender Pro is divided into two distinct product flavors to comply with Google Play Store policies while still offering full-featured automation for sideloaded/GitHub users:

| Feature / Permission | Play Store Variant (`playstore`) | GitHub Variant (`github`) |
| :--- | :---: | :---: |
| **`android.permission.READ_SMS`** | ❌ Removed | ✅ Enabled |
| **`android.permission.RECEIVE_SMS`** | ❌ Removed | ✅ Enabled |
| **`android.permission.POST_NOTIFICATIONS`** | ✅ Enabled | ✅ Enabled |
| **Transaction Auto-Sync Method** | Status Bar Notification Listener Service | Direct SMS Inbox Scan + Real-time SMS Stream + Notification Listener |
| **Google Play Compliance** | 100% Policy Compliant | Full Permissions (Sideload / GitHub) |

- **`playstore` Flavor:** Strips all restricted SMS (`READ_SMS`, `RECEIVE_SMS`, `SEND_SMS`) and Call Log permissions to meet Google Play Store requirements. Auto-sync relies exclusively on the Google Play-compliant Notification Listener Service.
- **`github` Flavor:** Retains full SMS permissions to allow one-click historical bank SMS importing and direct message folder scanning.

---

## 🚀 Running & Building Locally

### Play Store Variant
```bash
# Run on connected device
flutter run --flavor playstore

# Build Release APK
flutter build apk --flavor playstore --release

# Build Play Store App Bundle (AAB)
flutter build appbundle --flavor playstore
```

### GitHub Variant (Full Permissions)
```bash
# Run on connected device
flutter run --flavor github

# Build Release APK
flutter build apk --flavor github --release
```

---

## 🔄 CI/CD Deployment (GitHub Releases)

The GitHub Actions workflow [deploy_github_variant.yml](.github/workflows/deploy_github_variant.yml) automatically builds the **GitHub variant APK** (with full permissions) and publishes it directly to **GitHub Releases**.

### Triggering a Release:

#### Method 1: Via Git Tag (Recommended)
Pushing any tag formatted as `v*` (e.g. `v1.0.0`) automatically kicks off the build and creates a new GitHub Release:
```bash
git tag v1.0.0
git push origin v1.0.0
```

#### Method 2: Via GitHub Actions UI (Manual)
1. Go to your repository on GitHub: `https://github.com/arunk13398/Budget`
2. Click on the **Actions** tab.
3. Select **Deploy GitHub Variant to GitHub Releases** from the left sidebar.
4. Click **Run workflow**, enter any optional parameters (tag name, release notes, draft/prerelease flags), and click **Run workflow**.

---

### 🔑 Signing Keystore (Optional)

If configured in your GitHub repository secrets (**Settings -> Secrets and variables -> Actions**), the workflow automatically signs the release APK with your production keystore. If not configured, the workflow falls back to debug signing so that the output APK is always installable:

- `ANDROID_KEYSTORE_BASE64`: Base64-encoded keystore file (`base64 -i upload-keystore.jks`)
- `ANDROID_KEY_ALIAS`: Keystore key alias
- `ANDROID_KEY_PASSWORD`: Key password
- `ANDROID_STORE_PASSWORD`: Keystore store password
