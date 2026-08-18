# MultiSet AR — iOS App & App Clip: Design

**Status:** approved 2026-08-19 · **Scope of this spec:** Phase 0 + Phase 1
**Supersedes assumptions in:** `docs/multiset-ar-ios-build-prompt.md` §2.1, §2.2, §2.3, §4, §15

---

## 1. What we are building

A native SwiftUI iOS app plus an App Clip that turns MultiSet's VPS platform into
a thirty-second demo. Two audiences:

| Audience | Surface | Journey |
|---|---|---|
| SDK developer / customer | Full app | Sign in → browse maps & objects → test localization on site → publish an experience → get a QR |
| Anonymous end user | App Clip | Scan the QR at the venue → AR navigation or object tracking, no install, no account |

## 2. Findings that changed the plan

These were established by reading the live SDK at
`/Users/shyam/Developer/iOS-Xcode/MULTISET/multiset-ios-sdk`, the Dashboard's
API documentation, and the 91-endpoint Postman collection at
`/Users/shyam/Developer/Web/Multiset-Dashboard/`.

### 2.1 The Clip size budget is not a risk

`MultiSetSDK.xcframework/ios-arm64/MultiSetSDK` is **629 KB** (1.0 MB slice).
The build prompt's §2.3 `[VERIFY]` — "if the framework alone blows the budget,
the App Clip concept needs rethinking" — resolves in our favour. The Clip does
not link it anyway (§4.2 below), so the true budget consumer is our own code.

### 2.2 The "experience broker" already exists — do not build a backend

The build prompt specifies a custom broker at `clip.multiset.ai` that mints
scoped tokens, and calls it "a hard dependency [that] must be built alongside
the app." It already ships:

| Build prompt's invention | Platform reality |
|---|---|
| Broker minting short-lived scoped tokens | `GET /v1/auth/experience/{spaceCode}` — **auth: none** → `{token, expiresOn}` |
| Opaque, server-generated, revocable slug | Content Space `spaceCode` |
| Server-side kill switch | `PUT /v1/content-space/{id}/unpublish`, `…/private` |
| POI store | Content items of type `location_pin` (position/rotation/scale) |
| Experience manifest | `GET /v1/content-space/{spaceCode}` → space + contents |

**Consequence:** no server work, no database, no new hosting. The one genuine
gap is **nav graphs** — no API models a graph. They live in Content Space
`metadata` or as a JSON asset via `POST /v1/asset/upload`.

### 2.3 The SDK cannot be used in the App Clip

`MultiSetConfig.init` requires `clientId` **and** `clientSecret`. `authToken` is
get-only. There is no token-injection path, so under the no-secret-in-the-Clip
rule the Clip cannot link the SDK. This is the pivotal architectural constraint
and drives §4.2.

### 2.4 M2M auth alone cannot power the Library

The build prompt knows only `POST /v1/m2m/token`. But every M2M-reachable VPS
endpoint is a code-addressed singleton (`GET /v1/vps/map/{mapCode}`). The
**list** endpoints and analytics sit behind user login:

```
POST /v1/auth/login          → { accessToken, refreshToken, userId }
GET  /v1/vps/map?limit&page&query&status&fileType   ← §7.3 Library needs this
GET  /v1/vps/map-set?page&limit&search
GET  /v1/vps/object?page&limit&query
GET  /v1/account/analytics, /analytics/heatmap/{mapId}, /analytics/query-api
POST /v1/m2m, GET /v1/m2m    ← the app can mint its own SDK credentials
```

### 2.5 Endpoints the build prompt did not know about

- `GET /v1/account/analytics/heatmap/{mapId}?startDate&endDate` — a localization
  heatmap. Adopted as the app's signature element (§5.3).
- `GET /v1/account/analytics/query-api?mapId&startDate&endDate&limit&page`
- `POST /v1/vps/map/{mapId}/archive` · `/unarchive`
- `GET /v1/asset/all?type=3dmodel` · `GET /v1/file/sdk?key=`
- `POST /v2/vps/map` + `/v2/vps/map/complete-upload/{mapId}`
- ⚠️ `/v1/payment/*` exists. **It must not be referenced anywhere in the app**
  — App Store Guideline 3.1.1 prohibits steering to external purchase.

### 2.6 Corrections of record

- **No on-device localization on iOS.** `offlineBundle`,
  `process-offline-metadata` exist server-side, but the iOS SDK exposes no
  offline API. Every query is a round trip. (Build prompt §15 Q2 answered.)
- **`isRightHanded`** — the SDK docs say "always `false` for Unity". ARKit is
  right-handed, so native iOS most likely sends `true`. `[VERIFY]`
- **`mapCode` vs `mapSetCode`** — mutually exclusive per query; one session
  cannot serve both. (§15 Q3 answered.)
- **Content Space share URL** is already `https://app.multiset.ai/space/{spaceCode}`.

## 3. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Swappable pose provider** — one shared AR state machine + rendering; two pose sources | Clip cannot link the SDK (§2.3), but UX must not diverge (build prompt §2.5) |
| D2 | **Email/password sign-in, then silently mint M2M credentials** | Only path to the list/analytics endpoints (§2.4); developer never types a client ID |
| D3 | **`DeepLinkRouter` accepts both hosts**, config-driven | Unblocks all app work before an AASA file exists anywhere |
| D4 | **SF Pro + SF Mono, no bundled fonts** | Clip byte budget forbids bundled faces; per-target font divergence would make App and Clip look like different products; SF gets Dynamic Type and VoiceOver metrics right |
| D5 | **Heatmap + pose readout is the signature element** | One mono component reused in the AR HUD and Map Detail; backed by a real endpoint |
| D6 | **No backend** | §2.2 |

## 4. Architecture

### 4.1 Repo layout

```
MultiSet AR/
├─ MultiSet AR.xcodeproj          2 targets, xcconfig-driven
├─ App/                           com.multiset.ar
├─ Clip/                          com.multiset.ar.Clip
├─ Config/*.xcconfig              bundle IDs, versions, deployment target
├─ Packages/
│  ├─ MultiSetKit/                API, models, auth, keychain, deep links
│  ├─ MultiSetARCore/             pose providers, AR sessions, nav, rendering
│  └─ MultiSetUI/                 design system
├─ Vendor/MultiSetSDK.xcframework embedded in App only
└─ Scripts/                       clip size + secret-leak CI gates
```

### 4.2 The structural guarantee

`MultiSetARCore` has **zero SDK dependency**. It declares `PoseProvider` and
ships `RESTPoseProvider`. The SDK-backed conformance lives in the App *target*:

```
MultiSetARCore (package)              App target only
├─ protocol PoseProvider              └─ SDKPoseProvider: PoseProvider
├─ RESTPoseProvider ────────┐              └─ MultiSet.shared  ← xcframework
├─ ARExperience + state     │
├─ rendering / nav / A*     │         Clip target
└─ FrameCapture ────────────┘         └─ RESTPoseProvider only
```

The Clip *cannot* link the framework or reach a `clientSecret` — enforced by the
dependency graph, not by discipline. Both targets share one rendering layer and
one state machine, so build prompt §2.5 holds by construction.

### 4.3 Auth — three principals, one actor

```swift
enum AuthPrincipal: Sendable {
  case user(UserSession)              // login → access + refresh    [App]
  case machine(M2MSession)            // clientId/secret → m2m token [App → SDK]
  case experience(spaceCode: String)  // anonymous, no credentials   [Clip]
}
```

`AuthStore` is an `actor`. `validToken()` refreshes at T−5 min behind a
single-flight `Task` memo so concurrent callers cannot stampede the token
endpoint. Keychain (`.whenUnlockedThisDeviceOnly`) holds the refresh token and
the minted client secret; JWTs stay in memory only.

### 4.4 Model layer — two shape traps

Explicit `CodingKeys` throughout, because the API is inconsistent:

1. **Quaternion keys change by endpoint.** MapSet `relativePose.rotation` uses
   `qx/qy/qz/qw`; localization responses use `x/y/z/w`.
2. **The two localize endpoints return different shapes.** `query-form` nests
   under `localizationSuccess.position`; `multi-image-query` returns top-level
   `estimatedPose` + `trackingPose`. Both normalise to one `LocalizationResult`.

Dates arrive as `…T12:00:00.000Z` and `…T12:00:00Z` — the decoder tolerates both.

### 4.5 Error surface

```swift
enum MultiSetError: Error, Sendable {
  case unauthorized, forbidden, offline
  case notFound(resource: String)
  case rateLimited(retryAfter: TimeInterval?)
  case notLocalized(message: String)
  case network(URLError)
  case server(status: Int, message: String?)
  case decoding(context: String)
  case experienceUnavailable(ExperienceUnavailableReason)
}

enum ExperienceUnavailableReason: Sendable {
  case unknownCode, deactivated, mapProcessing, expired
}
```

`ExperienceUnavailableReason` makes the Clip's seven failure cases (build prompt
§9) a `switch` rather than ad-hoc strings.

### 4.6 Deep links

```swift
["app.multiset.ai":  .space,      // /space/{spaceCode}
 "clip.multiset.ai": .experience] // /e/{slug}
```

One `DeepLinkRouter` in `MultiSetKit`, shared by both targets, tested against
hostile inputs: wrong host, path traversal, unicode homoglyphs, missing code,
over-long code, embedded credentials.

## 5. Design system

### 5.1 Palette

Extracted from the Dashboard (`multiset-dashboard/src/app/globals.css`), not
approximated: accent `#7C3AED`, dark surface `#1E1B2E`, light surface `#F5F5F9`,
text `#111028`/`#4A4564`/`#7D7896`, borders `#E0DEE8`/`#ECEAF2`. The SDK sample
app uses `#7B2CBF`; we standardise on the Dashboard's `#7C3AED`.

Tokens only — semantic names, light and dark variants, no literal hex in views.

### 5.2 Type

SF Pro for text, SF Mono for map codes, pose values, confidence, and latency
(D4). Named roles: `display`, `title`, `headline`, `body`, `caption`, `mono`,
`monoLarge`.

### 5.3 Signature element

`PoseReadout` — a mono HUD block showing position, rotation, confidence,
latency, frames submitted, and ARKit tracking state — paired with
`LocalizationHeatmap`, a SwiftUI `Canvas` rendering of
`/v1/account/analytics/heatmap/{mapId}`. The same two components appear in the
AR overlay and on Map Detail. Everything else stays quiet.

### 5.4 Assets

Per `Assets/multiset-ar-asset-production-brief.md`: SF Symbols for all UI icons,
procedural RealityKit geometry for every AR overlay, SwiftUI shapes for the four
empty/error states, code-generated PDF for the QR sheet. The Clip's asset
catalog contains only an icon set — verified by a build-products grep.

## 6. Phase plan

| Phase | Deliverable | Done when |
|---|---|---|
| **0** | Both targets, three packages, design tokens, full model + mock API layer, previews, `ARCHITECTURE.md` | Both schemes build; every screen previews off mocks |
| **1** | SDK embedded, `SDKPoseProvider`, Clip size measured and recorded, both CI gates | Size number recorded; one localization session runs |
| 2 | Auth, Keychain, Library, Map Detail, localization HUD | A developer can sign in and localize in their own building |
| 3 | Nav graph, POI authoring, all three `ARExperience` modes | All three modes run from the parent app |
| 4 | Clip: invocation, manifest fetch, intro card, seven failure cases | A printed QR launches a working Clip |
| 5 | Publish flow, QR generation, PNG/PDF export, revoke | Publish → print → scan → navigate |
| 6 | Learn, Showcase, Settings, demo modes, `REVIEW_NOTES.md`, privacy manifest | Submission-ready |

## 7. Testing

- **Unit:** deep-link parsing incl. hostile inputs; model decoding against
  captured fixtures; token single-flight under concurrency; A* over nav graphs;
  pose transform math; multipart form encoding.
- **Verification:** `swift test` per package; `xcodebuild build` both schemes.
- **CI gates:** Clip ≤ 13 MB uncompressed; no credential string reachable from
  the built Clip binary.

## 8. Open `[VERIFY]` items

Recorded in `ARCHITECTURE.md`, resolved the moment credentials exist. None block
Phase 0.

1. Does the experience token authorise `/v1/vps/map/query-form` and
   `/multi-image-query`? **Gates the entire Clip.** If not, the Clip needs
   either an API scope change or the token-injection SDK change.
2. `isRightHanded` — `true` for ARKit?
3. Does an M2M token reach `GET /v1/vps/map` (list)?
4. Apple's current cap on registered advanced App Clip experiences per app.
5. Rate limiting on experience tokens — per code, per device, per hour.

## 9. Explicitly out of scope

- Any backend service (§2.2)
- Any reference to `/v1/payment/*` (§2.5)
- Map creation / upload flows — the existing App Store app owns capture
- On-device localization (§2.6)
