# Android Play Store Plan

Status date: May 2026
Target version: 0.7.0

## Goal

Add Android compatibility for OrthoQuant MD and prepare the app for Google Play distribution while keeping the iOS, iPadOS, macOS, and Android subscription experience aligned through RevenueCat.

## Current Decisions

- Distribution channel: Google Play.
- Android app name: `OrthoQuant MD`.
- Current application ID: `com.orthoquant.md`.
- Minimum SDK: 23.
- Camera is optional so devices without a camera can still install and use file/image import workflows.
- Android release notes should mention compatibility only after camera, gallery import, and share/open flows have been tested on real devices.

## Android Capabilities

- Camera capture through the Flutter camera plugin.
- Gallery/image import through the existing image picker flow.
- External image opening with Android `ACTION_VIEW` for `image/*`.
- External image sharing into the app with Android `ACTION_SEND` and `ACTION_SEND_MULTIPLE` for `image/*`.
- Android 13+ image permission support through `READ_MEDIA_IMAGES`.
- Legacy read permission support through `READ_EXTERNAL_STORAGE` for Android 12L and earlier.

## RevenueCat And Subscriptions

- Create or map Google Play subscription products to the same RevenueCat entitlement used by iOS, iPadOS, and macOS.
- Use the Android/Google Play RevenueCat API key in the Android build configuration before production release.
- Confirm one shared entitlement name for Pro access across all stores.
- Test restore/purchase behavior on a Google Play license test account.
- Verify that a user with Pro on one store sees the expected entitlement state when signed in with the same RevenueCat App User ID strategy.

## Local Verification

Before a Play Store build:

```bash
flutter test
flutter build apk --debug
```

Before production upload:

```bash
flutter build appbundle --release
```

The release App Bundle should only be uploaded after a real release keystore and signing configuration are added. The current Android release configuration still uses the debug signing config for local release builds, so it is not Play Store-ready yet.

## Release Signing Setup

Create an upload keystore locally. Do not commit the keystore or `android/key.properties`.

```bash
keytool -genkey -v \
  -keystore android/app/upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload
```

Then create `android/key.properties`:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD_OR_STORE_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
```

After this file exists, `flutter build appbundle --release` will use the release signing config instead of the local debug signing fallback.
For PKCS12 keystores, `keytool` may use the store password for both `storePassword` and `keyPassword`.

## Functional Test Matrix

- Launch app on an Android phone.
- Launch app on an Android tablet.
- Import an X-ray from gallery/files.
- Capture an image from camera.
- Share an image from the Android Photos/Gallery app into OrthoQuant MD.
- Open an image file with OrthoQuant MD from the Android file picker.
- Draw and edit manual measurements.
- Run the v0.7.0 clinical templates.
- Export/share the completed measurement image or report.
- Open What's New and Version History.
- Verify Pro access, paywall behavior, purchase, and restore flows.
- Verify permission prompts are understandable and only appear when needed.

## Google Play Console Steps

- Decide whether to keep the current application ID before first Play Console upload.
- Create the Google Play app record.
- Add a production release signing key or Play App Signing upload key.
- Configure Google Play billing products/subscriptions.
- Map Google Play products to the shared RevenueCat entitlement.
- Complete Data Safety and privacy declarations.
- Add screenshots for phone and tablet form factors.
- Upload the release App Bundle.
- Test with internal testing before production review.

## Open Items

- Create the release upload keystore and `android/key.properties`.
- Confirm final package/application ID.
- Configure Android-specific RevenueCat API key and Google Play products.
- Run real-device Android phone and tablet tests.
- Prepare Google Play screenshots and store metadata.
- Confirm Data Safety answers for camera, image access, purchases, analytics, and support links.
