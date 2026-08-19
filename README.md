# MultiSet AR

A native SwiftUI iOS app and App Clip over [MultiSet](https://www.multiset.ai)'s
Visual Positioning System.

Two audiences, one codebase:

| Audience | Surface | Journey |
|---|---|---|
| SDK developer | Full app | Sign in → browse maps and objects → test localization on site → publish an experience → get a QR code |
| Anyone | App Clip | Scan that code at the venue → AR navigation runs, no install, no account |

## Getting started

```sh
git clone <this repo> && cd "MultiSet AR"
open "MultiSet AR.xcodeproj"
```

Everything runs against fixtures out of the box — every screen previews without
credentials, and the three offline demos work on any device. To reach a real
account, sign in with your [developer portal](https://developer.multiset.ai/)
email and password.

### Requirements

| | |
|---|---|
| Xcode | 26.6+ |
| iOS | 16.0+ |
| Device | ARKit required for AR; the rest runs in the simulator |

## Verifying

```sh
./Scripts/verify.sh
```

Runs the unit tests for all three packages, builds both targets for Release, and
runs the two App Clip gates: uncompressed size ≤ 13 MB, and no credential
reachable from the Clip binary.

```sh
./Scripts/check-clip-secrets.sh --self-test   # proves the gate can still detect a leak
./Scripts/sync-app-icon.sh                    # re-copies the icon masters into both catalogs
```

## Project file

`MultiSet AR.xcodeproj` is **generated**. After adding or removing a source file:

```sh
python3 Scripts/generate-project.py
```

Build settings live in `Config/*.xcconfig` rather than in the project.

## Structure

```
App/            com.multiset.sdk — the full app, and the only target that links the SDK
Clip/           com.multiset.sdk.Clip — a launcher with three screens
Packages/
  MultiSetKit     API client, models, auth, keychain, deep links
  MultiSetVPS     the MultiSet VPS engine, ported to run on a bearer token
  MultiSetARCore  pose providers, AR session engine, nav, procedural rendering, AR views
  MultiSetUI      design tokens and shared components
Scripts/        project generation, icon generation, CI gates, verify
```

`MultiSetVPS` is the MultiSet SDK's own implementation, ported so its single
credential-bound seam — the `AuthManager` that exchanged a clientId and secret for a
token — is replaced by a token provider. Everything below it only ever needed a
bearer token, so localization, object tracking and the mesh overlay all run on the
signed-in user's access token, and on the App Clip's anonymous experience token.
`VPSConfig` has no credential properties, so a secret cannot reach the Clip by
construction. See [ARCHITECTURE.md](ARCHITECTURE.md).

## Documents

| | |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | How it fits together, the measured Clip size, open `[VERIFY]` items |
| [REVIEW_NOTES.md](REVIEW_NOTES.md) | Draft App Store review notes, including why live VPS cannot be tested off-site |
| [ASSETS.md](ASSETS.md) | Provenance for every asset, and what is still to produce |
| [docs/superpowers/specs/](docs/superpowers/specs/) | The design spec and the findings behind each decision |

## Licence

© 2026 MultiSet AI · All rights reserved.
`MultiSetSDK.xcframework` is licensed separately under the MultiSet License.
