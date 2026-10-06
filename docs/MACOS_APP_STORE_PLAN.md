# macOS App Store Plan

Status date: May 2026
Target version: 0.7.0

## Goal

Ship OrthoQuant MD as a native macOS Flutter app through the Mac App Store, preferably as an additional platform on the existing App Store Connect app record so iOS, iPadOS, and macOS can share the same app identity.

## Current Decisions

- Distribution channel: Mac App Store.
- Bundle ID: `com.orthoquant.orthoQuantMd`, matching the existing app identity.
- App name: `OrthoQuant MD`.
- macOS category: `public.app-category.medical`.
- Minimum macOS target in Xcode project: 11.0.
- Release build must keep App Sandbox enabled.

## macOS Entitlements

Release entitlements should stay minimal:

- `com.apple.security.app-sandbox`: required for Mac App Store distribution.
- `com.apple.security.network.client`: required for network-backed services such as purchases, links, and support flows.
- `com.apple.security.files.user-selected.read-write`: required for user-selected X-ray/image import and export flows.
- `com.apple.security.device.camera`: required if camera capture remains enabled on macOS.

Debug/profile-only entitlements may include development conveniences such as JIT or local network server access. These should not be added to Release unless there is a specific App Store-safe reason.

## Local Verification

Before App Store archive:

```bash
plutil -lint macos/Runner/Info.plist macos/Runner/Release.entitlements macos/Runner/DebugProfile.entitlements
flutter test
flutter build macos --release
```

On this Mac, the project path under `Documents` can add File Provider/Finder extended attributes to the generated `.app`, which makes `codesign` fail with `resource fork, Finder information, or similar detritus not allowed`. If that appears, build/archive from a checkout outside File Provider-managed folders, for example under `/tmp` or a local `~/Developer` folder.

After building:

```bash
codesign -dvvv --entitlements - build/macos/Build/Products/Release/OrthoQuant\ MD.app
```

Confirm the release app contains `com.apple.security.app-sandbox` and does not contain debug-only JIT/server entitlements.

## Functional Test Matrix

- Launch app on macOS.
- Import images with file picker.
- Import images with drag and drop.
- Draw and edit measurement templates.
- Save/export/share generated measurement output.
- Open version history and What's New.
- Verify Pro/purchase state on a sandbox App Store account.
- Verify offline behavior for already-opened local cases.
- Verify camera/photo permission prompts only appear when the feature is used.

## App Store Connect Steps

- Add macOS as a platform on the existing app record if universal purchase is desired.
- Confirm the macOS bundle ID matches the Xcode project bundle ID.
- Create or map macOS in-app purchase products/subscriptions as required by the store configuration.
- Add macOS screenshots and platform-specific metadata.
- Complete privacy questionnaire for macOS data collection and permissions.
- Archive from Xcode using the Release configuration.
- Validate and upload the archive through Xcode Organizer or Transporter.
- Test the uploaded build with TestFlight or App Store Connect internal testing before review.

## Open Items

- Confirm Apple Developer Team ID and signing certificates on this Mac.
- Confirm whether macOS subscriptions should share the current RevenueCat offering or use separate macOS product IDs.
- Decide whether camera capture is truly needed on macOS; if not, remove the camera entitlement and usage text before submission.
- Prepare macOS App Store screenshots in the required sizes.
- Run a real sandbox purchase test on macOS.
