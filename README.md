# 📸 Face Attendance App — Flutter

A Flutter face recognition attendance system using **Google ML Kit** for liveness detection and the SmartWorker `auth_verification` API for identity matching.

---

## ✅ Features

| Feature | Detail |
|---|---|
| Google ML Kit Face Detection | Real-time via camera stream |
| Face Liveness Detection | Eyes open + head angle + face size checks |
| "It's not a face" detection | Shows message if no face found |
| Face must be straight | Euler angle < 20° enforced |
| Auto torch on scan start | Turns on automatically, manual toggle too |
| Bearer Token auth | Hardcoded in `auth_service.dart` |
| Base64 + SHA-256 hash sent to API | Both image and hash included in request |
| Authenticated → Home Screen | Simple welcome + live date/time |
| Not Authenticated → Error message | Clear "Not Authenticated" feedback |

---

## 📁 Project Structure

```
lib/
├── main.dart
├── screens/
│   ├── splash_screen.dart       # Animated splash
│   ├── attendance_screen.dart   # Camera + liveness + API verify
│   └── home_screen.dart         # Welcome message + date/time
├── services/
│   ├── auth_service.dart        # API call with Bearer token
│   └── face_liveness_service.dart  # ML Kit face analysis
└── widgets/
    ├── face_overlay_painter.dart   # Oval guide + scan line
    └── scan_status_widget.dart     # Status bar in camera view
```

---

## ⚙️ Setup

### 1. Install dependencies
```bash
flutter pub get
```

### 2. Android — `android/app/build.gradle`
```gradle
android {
    compileSdkVersion 34
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
    }
}
```

### 3. iOS — `ios/Podfile`
```ruby
platform :ios, '14.0'
```
Then:
```bash
cd ios && pod install
```

### 4. Run
```bash
flutter run
```

> ⚠️ Use a **physical device** — ML Kit face detection does not work on emulators.

---

## 🔐 API Details

**Endpoint:** `POST https://myb-v4.smartworker.app/secure_api/auth_verification`  
**Auth:** `Authorization: Bearer tppVqNBOFw1ydtAcxRVXlL6FJLWtyN3bIlBbh--rVkKZsZs9UmxomvXKMeguKUS3`

**Request body:**
```json
{
  "face_image": "<base64_encoded_jpeg>",
  "face_hash":  "<sha256_base64_hash>",
  "timestamp":  "2024-03-03T09:00:00.000Z"
}
```

The app handles 4 different API response formats automatically (see `auth_service.dart`).

---

## 🔦 Torch Behaviour

- Torch turns **ON automatically** when scanning starts
- Manual **⚡ toggle** button appears in top-right during scanning
- Turns **OFF** after capture or cancel

# Face_detection