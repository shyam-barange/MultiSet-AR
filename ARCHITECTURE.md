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

The app has two ways to run an AR session, because the two audiences have
incompatible constraints.

| | Driven by | Used for | Mesh overlay |
|---|---|---|---|
| **SDK path** | `MultiSetSDK` v1.15.0 via `MultiSetARView` | Test localization and Test tracking, from Map and Object Detail | Yes — the SDK downloads and renders it |
| **REST path** | `MultiSetARCore`'s `RESTPoseProvider` | Hosted experiences, in the app *and* the App Clip | No |

**The SDK must be initialized before `MultiSetARView` is built.** The view hands
the SDK its AR session, mesh parent, object anchor and gizmo update handler from
`makeUIView`, and every one of those forwards through `internalManager?` — so if
the SDK is not initialized yet, all four are dropped in silence. The result is a
camera preview that can never localize: no frames reach the SDK, and nothing moves
the gizmo the mesh is parented to. The SDK documents the requirement on
`MultiSetARView` itself.

`SDKRunner` therefore owns the `SDKSession`, starts it once credentials resolve,
and only builds the screen — and so the AR view — once `isSDKInitialized` is true.
The screens assert it on appear, because the failure is otherwise invisible.

**The SDK path lets the SDK own the AR session.** `MultiSetARView` installs the
SDK's own `ARSession` delegate, creates the gizmo anchor that map meshes are
parented to, adds a separate world-fixed anchor for object meshes, and adds
lighting. The mesh pipeline only works if the SDK sets the scene up itself, so
these screens embed `MultiSetARView` rather than the app's own `ARSceneHost`.

With `meshVisualization` on, the SDK does the whole mesh pipeline internally:
`GET /v1/vps/map/{mapCode}` for the mesh link, `GET /v1/file?key=` for a signed
URL, GLB download with an on-disk cache, then render under the gizmo anchor with a
reveal animation — and for a MapSet, applying the localized map's `relativePose`.
Object tracking does the same through `objectMesh.meshLink` and renders an outline
traced along the real object's silhouette. The app subscribes to `onMeshLoaded` and
`onObjectMeshLoaded` and reports mesh state in the HUD separately from fix state,
because a fix can succeed while the mesh is still downloading.

v1.15.0 also brings pose-consistency checking. When the server returns a pose that
contradicts the device's own motion by more than `poseConsistencyThreshold`, the SDK
discards it and calls `onLocalizationFalsePositive` instead of success or failure —
nothing in the scene moves. That is surfaced as its own state, since treating it as
a failure would be wrong: the request succeeded.

An earlier attempt drove the SDK from the app's own `ARView` with
`meshVisualization` off. That could never render a mesh and was the wrong shape for
the SDK's ownership model; it has been removed.

**The REST path stays** because the App Clip cannot link the SDK at all, for the
reason below — and because it is the fallback when SDK credentials cannot be
created.

### Credentials for the SDK path

`MultiSetConfig` takes a clientId and clientSecret and has no way to accept a
bearer token, so a signed-in user's access token cannot drive the SDK directly.
What it can do is *create* SDK credentials: a signed-in user already has the
authority for `POST /v1/m2m`, so the app mints a query-scoped pair for itself at
sign-in and again on demand. Nobody is ever asked to paste a client ID.

Two shape errors made every mint fail, which is what produced the
"SDK credentials needed" dead end:

- The request sent `name` and no `scope`. Both `clientName` and `scope` are
  required, so the server rejected it.
- The response decoder required an `_id` that the 201 body does not contain, so
  even a successful mint failed to decode.

Both are now pinned by tests against the shapes in the API's own Postman
collection, including the 201 status and the fact that a listed client never
carries a secret — which is why an existing client cannot be reused.

If minting genuinely cannot succeed — a plan that disallows it, for instance — the
screen falls back to REST localization driven by the user's own access token rather
than dead-ending, and says so. The mesh overlay is the one capability lost: the SDK
renders it with a hand-written glTF parser and a Metal shader, which the REST path
has no equivalent of and which is not worth reimplementing.

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
