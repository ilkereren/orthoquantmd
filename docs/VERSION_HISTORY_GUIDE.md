# Version History Guide

This file keeps the release-history workflow explicit so the in-app "What's new" and Settings > Version History stay consistent.

## Current Source

- App version: `pubspec.yaml`
- In-app release notes: `lib/screens/settings_screen.dart`
- Home "What's new" summary: `lib/main.dart`
- Android release readiness: `docs/ANDROID_PLAY_STORE_PLAN.md`
- macOS release readiness: `docs/MACOS_APP_STORE_PLAN.md`

## Update Checklist

1. Update `pubspec.yaml` with the new version and build number.
2. Add the newest release as the first item in `_showVersionHistory`.
3. Mark the newest version as highlighted in `_buildVersionTimelineItem`.
4. Update the Home "What's new" panel with only user-facing changes.
5. Keep developer/test-only changes out of "What's new".
6. Set the release month and year using the public release target, for example `May 2026`.
7. Run `dart format` on edited Dart files.
8. Run `flutter test`.
9. Restart the web server after changing `pubspec.yaml`, because app version metadata may not refresh with hot restart alone.

## Writing Rules

- Use one short heading per release, for example `v0.7.0`.
- Keep the newest release at the top.
- Group related templates into one user-friendly bullet when possible.
- Prefer clinical/user benefit language over implementation language.
- Avoid mentioning local test flags, debug-only behavior, or web-only development fixes unless they are public user features.

## Current v0.7.0 Notes

- AI implementation: OrthoQuant AI can interpret measurement results with physician-verification guidance and configurable AI settings.
- New clinical templates: Cervical Spine Lateral, Post-op Hip Arthroplasty Checks, and TKA Alignment Checks.
- Native macOS app foundation prepared for Mac App Store distribution.
- iPadOS compatibility improvements for larger screens and simulator/device builds.
- Upcoming: Android compatibility groundwork for camera, gallery import, and image sharing/opening flows.
- Minor bug fixes and rendering refinements.
