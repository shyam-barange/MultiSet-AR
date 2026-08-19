# Architecture

MultiSet AR is a SwiftUI iOS app plus an App Clip over MultiSet's VPS platform.
The full app is a field tool for developers; the Clip is the payoff — a stranger
scans a printed code at a venue and AR navigation runs with no install and no
account.

Design decisions and the findings behind them are in
[`docs/superpowers/specs/2026-08-19-multiset-ar-ios-design.md`](docs/superpowers/specs/2026-08-19-multiset-ar-ios-design.md).

## Layout

```
MultiSet AR/
├─ MultiSet AR.xcodeproj        generated — see Scripts/generate-project.py
├─ App/                         com.multiset.sdk
├─ Clip/                        com.multiset.sdk.Clip
├─ Config/*.xcconfig            build settings as text
├─ Packages/
│  ├─ MultiSetKit/              API, models, auth, keychain, deep links
│  ├─ MultiSetARCore/           pose providers, AR sessions, nav, rendering, AR views
│  └─ MultiSetUI/               design system
├─ Vendor/                      MultiSetSDK.xcframework, wrapped as a SwiftPM binary target
└─ Scripts/                     project generation, icon generation, CI gates
```

`MultiSet AR.xcodeproj` is **generated**. After adding or removing a source file:

```sh
python3 Scripts/generate-project.py
```

Hand-editing the project file works but will be overwritten. Build settings live
in `Config/*.xcconfig`, not in the project.

## Identifiers

| | |
|---|---|
| Parent bundle ID | `com.multiset.sdk` |
| App Clip bundle ID | `com.multiset.sdk.Clip` |
| Associated domain, app | `applinks:api.multiset.ai` |
| Associated domain, Clip | `appclips:api.multiset.ai` |
| Custom scheme | `multisetar://` |
| Device family | `1,2` on **both** targets — Apple requires the Clip's `UIDeviceFamily` to equal its parent's. iPad's all-orientations rule is met with `UISupportedInterfaceOrientations~ipad` in `Clip/Info.plist`, not by narrowing the Clip to iPhone. |

The prefix lives once, in `Config/Shared.xcconfig` as
`MULTISET_BUNDLE_ID_PREFIX`; both targets derive from it.

## Two AR paths, and why

| | Driven by | Used for | Mesh overlay |
|---|---|---|---|
| **Engine path** | `MultiSetVPS` — the SDK's own implementation, ported | Test localization and Test tracking, from Map, Map Set and Object Detail | Yes |
| **REST path** | `MultiSetARCore`'s `RESTPoseProvider` | Hosted experiences, in the app *and* the App Clip | No |

### `MultiSetVPS`: the SDK, ported to run on a bearer token

`MultiSetConfig` in the shipped framework takes a `clientId` and `clientSecret` and
has no way to accept a token, so the SDK could only ever run as an M2M client. But
nothing *below* its `AuthManager` needed those credentials: the token appears in
exactly eight places, as `Bearer <token>`. `AuthManager` was the only
credential-bound part of the whole SDK.

So the engine is ported from `iOS-SDK-Internal/MultiSetSDK` with that one seam
replaced by `VPSTokenProviding`. Everything else — `LocalizationManager`,
`ObjectTrackingManager`, `PoseConsistencyGate`, the glTF parser, both Metal shaders,
the reveal animator, the outline renderer — is the SDK's own code.

That single change is what makes the flows work for a signed-in user:

- **The app** authenticates as the signed-in user, via `AuthStore`. No M2M
  credentials, nothing to mint, nothing to paste.
- **The App Clip** can run the same engine on its anonymous experience token, mesh
  overlay included — a capability the REST path never had.

`VPSConfig` has no credential properties at all, so a secret cannot reach the engine
or the Clip by construction rather than by discipline.

A token is refreshed before every localization and tracking run, not once at setup.
A user access token lasts 30 minutes while a session with background
re-localization can run far longer; `AuthStore` refreshes from the refresh token,
single-flighted so concurrent requests cannot race a rotating one.

The vendored `MultiSetSDK.xcframework` is gone — nothing links it now.

**The engine must be initialized before `VPSARView` is built.** The view hands it
the AR session, mesh parent, object anchor and gizmo update handler from
`makeUIView`, and each forwards through an optional internal manager — so building
the view first drops all four in silence, leaving a camera preview that can never
localize. `SDKRunner` starts the session before rendering the screen, and the
screens assert it on appear.

**Shaders load from `Bundle.module`, not `Bundle(for:)`.** In a statically linked
package the latter resolves to the app bundle, where there is no `default.metallib`
— the load fails, the renderer falls back to a plain material, and the reveal and
outline effects are silently lost. A test asserts all three shader functions load.

### What the mesh pipeline does

On a successful fix, with `meshVisualization` on: `GET /v1/vps/map/{mapCode}` for
the mesh link, `GET /v1/file?key=` for a signed URL, GLB download with an on-disk
cache, parse through the engine's own glTF reader, then render under the gizmo
anchor with a radial reveal — and for a map set, applying the localized map's
`relativePose`. Object tracking does the same through `objectMesh.meshLink` and
renders an outline traced along the real object's silhouette, parented to a
world-fixed anchor rather than the gizmo. Mesh state is reported in the HUD
separately from fix state, because a fix can succeed while the mesh is still
downloading.

v1.15.0's pose-consistency check is included: a server pose contradicting the
device's own motion by more than `poseConsistencyThreshold` is discarded via
`onLocalizationFalsePositive` rather than applied. That is surfaced as its own
state, since the request succeeded and nothing in the scene moved.

## The constraint that shapes everything

`MultiSetConfig.init` requires a `clientId` **and** a `clientSecret`, and
`MultiSet.authToken` is get-only — the SDK has no token-injection path. The Clip
runs for anonymous strangers, so an SDK-linked Clip would have to carry a
credential that anyone scanning the code could extract and bill to the
developer's account.

So the SDK is never linked into the Clip. That is enforced by the dependency
graph rather than by convention:

```
MultiSetARCore (package, no SDK)          App target only
├─ protocol PoseProvider                  └─ SDKPoseProvider: PoseProvider
├─ RESTPoseProvider ──────────┐                └─ MultiSet.shared  ← xcframework
├─ ARExperience + state       │
├─ rendering / nav / A*       │           Clip target
├─ shared AR views            │           └─ RESTPoseProvider only
└─ FrameCapture ──────────────┘
```

Both targets share one state machine, one HUD, and one renderer, so their
behaviour cannot drift. Only the pose source differs.

`Config/App.xcconfig` carries `FRAMEWORK_SEARCH_PATHS` and the
`MultiSetSDKBinary` package dependency; `Config/Clip.xcconfig` deliberately
carries neither, so the Clip cannot resolve the module even by accident.

## Auth: three principals

The platform has three credential models, and the app models all three
explicitly rather than pretending there is one.

```swift
enum AuthPrincipal {
  case user(UserSession)              // POST /v1/auth/login → access + refresh
  case machine(AuthToken)             // POST /v1/m2m/token, Basic clientId:secret
  case experience(spaceCode:, token:) // GET /v1/auth/experience/{code} — no credential
}
```

- **The app** signs in with dashboard credentials, then silently calls
  `POST /v1/m2m` to mint M2M credentials for the SDK. Nobody types a
  forty-character secret on glass.
- **The Clip** only ever holds `.experience`.

Why not M2M alone, as the build prompt assumed: every M2M-reachable VPS endpoint
is a code-addressed singleton (`GET /v1/vps/map/{mapCode}`). The **list**
endpoints the Library needs, and all analytics, sit behind user login.

`AuthStore` is an actor. `validToken()` refreshes at T−5 min behind a
single-flight `Task` memo, so a burst of concurrent 401s causes one token request
rather than one each.

## No backend

The build prompt specifies a custom "experience broker" and calls it a hard
dependency. It already ships:

| Build prompt's invention | Platform reality |
|---|---|
| broker minting scoped tokens | `GET /v1/auth/experience/{spaceCode}` — auth: none |
| opaque revocable slug | Content Space `spaceCode` |
| server-side kill switch | `PUT /v1/content-space/{id}/unpublish`, `…/private` |
| POI store | Content items of type `location_pin` |
| experience manifest | `GET /v1/content-space/{spaceCode}` |

The one real gap is nav graphs — no API models a graph. This app stores its extra
fields in the Content Space `metadata` bag under `msar.*` keys
(`ExperienceManifestBuilder.MetadataKey`). Anything absent falls back to a
default, so a space created in the web dashboard still opens.

## Deep links

`api.multiset.ai` serves the `apple-app-site-association` file, so it is the only
host whose links can launch the Clip, and it is what generated QR codes encode
(`ContentSpace.shareURL`). The other two stay recognised so an older printed code,
or a URL pasted from the dashboard, keeps working.

| Host | Accepted paths | Role |
|---|---|---|
| `api.multiset.ai` | `/space/{code}`, `/e/{code}` | AASA host — Clip invocations arrive here |
| `app.multiset.ai` | `/space/{code}` | the platform's own web share URL |
| `clip.multiset.ai` | `/e/{code}` | reserved |

One `DeepLinkRouter` in `MultiSetKit`, shared by both targets, so the app and the
Clip cannot disagree about what a link means. Tested against hostile input: wrong
host, lookalike host suffixes (`api.multiset.ai.evil.com`), path traversal,
unicode homoglyphs, missing code, over-long code, embedded credentials in the
authority, and mismatched host/prefix pairs. A URL must have exactly two path
segments — accepting extra ones would silently truncate a malformed URL into a
valid-looking code.

`?mode=` is a testing override only. The canonical mode lives in the manifest, so
a stale printed QR cannot pin the wrong one.

**One consequence worth deciding on.** `api.multiset.ai` also serves the REST API,
so a scan on Android or in a desktop browser hits the API rather than a landing
page. Either add a `/space/{code}` route on that host that redirects to the web
experience, or accept that non-iOS scans get an API response.
`ContentSpace.webURL` carries the `app.multiset.ai` form for that purpose.

## Two API shape traps

Handled explicitly, because both would fail silently:

1. **Quaternion keys differ by endpoint.** `qx/qy/qz/qw` in MapSet
   `relativePose`; `x/y/z/w` in localization responses. `Rotation` decodes both.
2. **The two localize endpoints return different shapes.** `query-form` nests the
   pose under `localizationSuccess`; `multi-image-query` returns it at the top
   level. Both normalise into one `LocalizationResult`.

Dates arrive as both `…T12:00:00.000Z` and `…T12:00:00Z`.

## Coordinate transform

A VPS result is the pose of the *camera* in map space. Anchoring content means:

```
worldFromMap = worldFromCamera · (mapFromCamera)⁻¹
```

Both terms must describe the same instant. A multi-frame query takes several
hundred milliseconds, during which the device moves, so `PoseTransform` prefers
the server's `trackingPose` — the ARKit pose it actually matched — over wherever
the camera is when the reply lands. Using the live transform would bake in an
error equal to however far the user walked mid-query.

## Clip budget

Measured on a Release device build:

| | |
|---|---|
| App Clip, uncompressed | **3.25 MB** |
| CI gate | 13 MB (Apple's limit is 15 MB on iOS 16+) |
| `MultiSetSDK` arm64 binary, for reference | 629 KB — not in the Clip |

The build prompt flagged SDK size as a risk that could sink the Clip concept.
It is not one.

Every AR overlay — path ribbon, chevrons, POI markers, object outlines, origin
gizmo — is generated at runtime, and the Clip's asset catalog holds only an icon
set and two colours. The photographic imagery lives in the app target's catalog
alone; the App Clip card header goes to App Store Connect rather than into any
bundle. Both facts are gated by `Scripts/check-bundled-assets.sh`, which reads the
compiled `Assets.car` of each product. Adding the shared catalog to the Clip's
membership takes the Clip from 3.3 MB to 24.6 MB — past Apple's 15 MB limit — so
the gate was self-tested by deliberately making that mistake and confirming it
fires.

Asset layout, the HEIC-versus-PNG measurement, and the On-Demand Resources split
that takes the app from 31 MB to 18 MB are documented in
[ASSETS.md](ASSETS.md).

### Clip surface — known limitation

`MultiSetKit` is one module, so the Clip links all of it. Verified against a
Release build:

- `/v1/m2m/token` and `/v1/auth/login` are **absent** — nothing in the Clip
  reaches them and the linker strips them. `Scripts/check-clip-secrets.sh`
  asserts this, so it becomes a regression guard.
- `M2MCredentials` and `M2MClient` remain as **type metadata** (field names, not
  values). No credential value is present.

This is not a leak, but it is unreachable credential machinery in a binary that
runs for strangers. Removing it means splitting `MultiSetKit` into a core module
and an account module that only the app links. That touches `MultiSetAPI`,
`LiveMultiSetAPI`, and `MockMultiSetAPI`, so it is deferred rather than done
half-way — worth doing before the Clip ships publicly.

## Verification

```sh
./Scripts/verify.sh                          # tests, Release build, both gates
./Scripts/check-clip-secrets.sh --self-test  # proves the gate can still detect a leak
```

161 unit tests cover deep-link parsing against hostile input, model decoding
against payloads copied from the live API docs, token single-flighting under
concurrency, A* including cost overrides, the pose transform, intrinsics scaling,
and the thermal policy.

## Open `[VERIFY]` items

None block the work done so far. Each needs credentials or a mapped site.

| # | Question | Why it matters |
|---|---|---|
| 1 | Does the experience token authorise `/v1/vps/map/query-form` and `/multi-image-query`? | **Gates the entire Clip.** If not, the Clip needs an API scope change or a token-injection SDK change. |
| 2 | Is `isRightHanded: true` correct for ARKit? | The SDK docs only ever show Unity sending `false`. If poses come back mirrored, `PoseTransform.flippingHandedness` is the correction. |
| 3 | Does an M2M token reach `GET /v1/vps/map` (list)? | Would allow an M2M-only sign-in path. |
| 4 | Apple's current cap on registered advanced App Clip experiences per app | Bounds how many venues one app can serve. |
| 5 | Rate limiting on experience tokens, per code and per device | Abuse policy for public codes. |

## Deliberately out of scope

- Any backend service — the platform already provides it.
- Any reference to `/v1/payment/*`. It exists in the API but steering to external
  purchase breaks App Store Guideline 3.1.1.
- Map creation and upload — the existing App Store app owns capture.
- On-device localization. `offlineBundle` and `process-offline-metadata` exist
  server-side, but the iOS SDK exposes no offline API, so every query is a round
  trip.
- The 3D showcase sandbox. It needs 4–6 licensed USDZ models, and the asset brief
  is explicit that generated 3D is not production quality for AR. Sourcing with
  recorded licences is the blocking step, not the code.
- Phases 2–6 of the build prompt beyond what is built here: POI authoring on a
  map, nav-graph editing, and the full publish round trip against a live account.
