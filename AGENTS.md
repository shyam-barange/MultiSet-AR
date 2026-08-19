# Repository Guidelines

## Project Structure & Module Organization

`App/` contains the full SwiftUI application and is the only target that links `MultiSetSDK`. `Clip/` contains the credential-free App Clip. Shared code lives in three local Swift packages: `MultiSetKit` for API, authentication, models, and deep links; `MultiSetARCore` for AR sessions, navigation, rendering, and pose-provider abstractions; and `MultiSetUI` for design tokens and reusable components. Package tests are under `Packages/<Package>/Tests/`. Build settings belong in `Config/*.xcconfig`; third-party binaries live in `Vendor/`. Production artwork is documented in `ASSETS.md` and stored under `ProductionAssets/` or target asset catalogs.

The checked-in `MultiSet AR.xcodeproj` is generated. After adding, removing, or relocating source files, run `python3 Scripts/generate-project.py` instead of hand-editing the project.

## Build, Test, and Development Commands

- `open "MultiSet AR.xcodeproj"` opens the app and App Clip schemes in Xcode.
- `./Scripts/verify.sh` runs all package tests, builds both targets in Release, and checks Clip size, credentials, and bundled assets.
- `cd Packages/MultiSetKit && xcodebuild test -scheme MultiSetKit -destination "platform=iOS Simulator,name=iPhone 17"` runs one package's tests; substitute `MultiSetUI` or `MultiSetARCore`. Plain `swift test` does not work — the packages declare `.iOS` only, so SwiftPM builds them for macOS and fails on availability.
- `xcodebuild build -project "MultiSet AR.xcodeproj" -scheme "MultiSet AR" -configuration Release -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO` performs a non-signing release build.
- `./Scripts/check-clip-secrets.sh --self-test` verifies that the credential-leak gate itself works.

## Coding Style & Naming Conventions

Use standard Swift formatting with four-space indentation and one primary type per file. Name types in `UpperCamelCase`, members in `lowerCamelCase`, and XCTest methods as `testBehaviorUnderCondition`. Preserve Swift concurrency boundaries, especially actor-isolated authentication state. No repository-wide formatter or linter is configured; follow nearby code and keep Xcode warnings clean.

## Testing Guidelines

Tests use XCTest. Add focused regression tests beside the owning package and keep fixtures deterministic and offline. There is no numeric coverage threshold, but new parsing, authentication, navigation, or transform behavior should include success and failure cases. Run `./Scripts/verify.sh` before submitting changes; ARKit behavior still requires validation on a compatible device.

## Commit & Pull Request Guidelines

Recent commits use concise, imperative summaries such as `Add MultiSetUI and MultiSetKit packages`. Keep each commit scoped to one coherent change. Pull requests should explain user-visible and architectural impact, identify tests run, link relevant issues, and include screenshots or recordings for UI/AR changes. Call out asset-size changes and any effect on the App Clip's no-SDK, no-secret boundary.

## Security & Configuration

Never place client secrets in source, asset catalogs, fixtures, or Clip resources. Keep SDK-backed providers in `App/`; the Clip must use credential-free APIs through shared abstractions.
