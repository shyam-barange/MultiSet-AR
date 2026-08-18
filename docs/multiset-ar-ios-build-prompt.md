# Build Prompt — MultiSet AR (iOS, SwiftUI + App Clip)

> **How to use this document**
> Paste the whole thing as the opening prompt to a coding agent (Claude Code, Cursor, Xcode assistant). It is written to be executed in phases — instruct the agent to complete Phase 0 and stop for review before writing feature code. Sections marked **[VERIFY]** contain assumptions the agent must confirm against live docs or the SDK source before building on them.

---

## 1. Mission

Build `MultiSet AR`, a native SwiftUI iOS app that turns MultiSet's VPS platform into something a developer can **demo in thirty seconds and hand to a stranger**.

Two audiences, one codebase:

| Audience | Surface | Journey |
|---|---|---|
| **SDK developer / MultiSet customer** | Full app | Sign in with credentials → browse their maps and tracked objects → test localization on site → publish a hosted experience → get a QR code |
| **Anonymous end user** | App Clip | Scan that QR at the venue → AR navigation or object tracking runs, no install, no account |

The developer-facing half is a **field tool**. The App Clip is the **payoff** — proof to a prospect that their map works, delivered without a download.

---

## 2. Non-negotiables — read before writing any code

These five constraints shape the architecture. Violating any of them means a rewrite or an App Store rejection.

### 2.1 The App Clip must never see a client secret

The Clip runs for anonymous strangers. A `clientSecret` in a QR URL, in the Clip bundle, or in a bundled plist is a credential leak that bills the developer's account. Anyone who scans the code can read the URL.

**Required design:** a backend **experience broker** holds developer credentials and mints short-lived, single-map, query-scoped tokens.

```
GET https://clip.multiset.ai/v1/experience/{slug}
→ 200 {
    slug, mode, mapCode | mapSetCode, target,
    branding: { title, subtitle, accentHex, logoURL },
    pois: [...], navGraph: {...},
    sessionToken: "<JWT — this map only, query only, ~15 min>",
    expiresOn: "2026-08-19T12:00:00Z"
  }
```

This broker **does not exist yet**. It is a hard dependency and must be built alongside the app. The agent must not work around its absence by embedding credentials — instead, build against a documented mock (`Phase 0`) and keep the contract in one file so the real endpoint drops in cleanly.

### 2.2 Invocation domain is `clip.multiset.ai`, not `api.multiset.ai`

The proposed `https://api.multiset.ai/{devId}/{mapId}?mode=nav&target={poiId}` has three problems:

- **Associated Domains** and the AASA file would sit on the production API host. Keep user-facing deep-link infrastructure off the API domain.
- `devId` in a public URL leaks tenant structure and makes experiences enumerable.
- Path params can't be revoked without breaking the printed QR.

**Use instead:** `https://clip.multiset.ai/e/{slug}` where `slug` is an opaque, server-generated, revocable identifier (e.g. `k7m2p9xq`) resolving server-side to dev + map + mode + target. Optional human-readable vanity slugs are fine (`toit-brewery`) as long as they're server-issued, not derived from IDs.

Keep `?mode=` as an *optional override* for testing only; the canonical mode lives in the manifest.

### 2.3 15 MB uncompressed App Clip budget

iOS 16+ allows 15 MB. ARKit plus the MultiSet SDK plus RealityKit will consume most of it. Therefore:

- **Zero bundled 3D assets in the Clip.** Path meshes, arrows, and markers are generated procedurally in code. Any venue-specific model streams from the manifest URL at runtime.
- No analytics SDKs, no image assets beyond an icon set, no fonts beyond system faces.
- Add a CI check that fails the build if the Clip's uncompressed size exceeds 13 MB (2 MB headroom).

**[VERIFY]** Measure the MultiSet iOS SDK's contribution to binary size early — Phase 1, not Phase 5. If the framework alone blows the budget, the App Clip concept needs rethinking before more work goes in.

### 2.4 The App Store reviewer cannot travel to a mapped site

VPS localization requires physical presence at a scanned location. A reviewer in Cupertino will open the app, see a camera feed that never localizes, and reject under Guideline 2.1 / 4.2. **Offline demo modes are a shipping requirement, not a nice-to-have.** See §11.

### 2.5 The Clip is a subset of the parent, never a superset

Apple reviews App Clip experiences against the parent app. Every capability in the Clip — navigation, object tracking, localization — must be reachable in the full app too.

---

## 3. Project structure

```
MultiSetAR/
├─ MultiSetAR.xcodeproj
├─ App/                          # Parent target — com.multiset.ar
│  ├─ MultiSetARApp.swift
│  ├─ Features/
│  │  ├─ Onboarding/
│  │  ├─ Auth/
│  │  ├─ Library/                # Maps + Objects browsing
│  │  ├─ Publish/                # Experience hosting + QR
│  │  ├─ Showcase/               # 3D model AR sandbox
│  │  ├─ Learn/                  # Platform, tech, SDKs
│  │  └─ Settings/
│  └─ Resources/
├─ Clip/                         # App Clip target — com.multiset.ar.Clip
│  ├─ MultiSetARClipApp.swift
│  ├─ InvocationRouter.swift
│  └─ ClipShellView.swift
└─ Packages/
   ├─ MultiSetKit/               # API client, models, token store
   ├─ MultiSetAR-Core/           # AR sessions: localize / navigate / track
   └─ MultiSetUI/                # Design system, shared components
```

**Targets and identifiers**

| | |
|---|---|
| Parent bundle ID | `com.multiset.ar` |
| Clip bundle ID | `com.multiset.ar.Clip` |
| Display name | `MultiSet AR` |
| Deployment target | iOS 16.0 (matches SDK requirement) |
| Swift | 5.9+, strict concurrency, `async/await` throughout |
| UI | SwiftUI + Observation (`@Observable`), UIKit bridging only where ARKit demands it |
| AR | ARKit + RealityKit |
| Dependencies | MultiSet iOS SDK (local XCFramework), everything else first-party. No Alamofire, no SnapKit. |

The three local Swift packages are what make the Clip viable — the Clip imports `MultiSetKit` and `MultiSetAR-Core` only, never `App/`.

---

## 4. Reference material

Read these before designing the networking layer. Do not invent endpoint shapes.

- **iOS SDK + sample views:** https://github.com/MultiSet-AI/multiset-ios-sdk — study `SDKConfig.swift`, `LandingView`, `ARLocalizationView`, `ARObjectTrackingView`. This is the closest thing to a reference implementation; mirror its session lifecycle rather than reinventing it.
- **Docs index for LLM ingestion:** https://multiset.gitbook.io/multiset/llms.txt — pull this first, it maps the whole doc tree.
- **REST API:** https://docs.multiset.ai/multiset/basics/rest-api-docs — child pages cover Authentication, Map Query, Map Details, MapSet, Object Tracking Query, Simulation Data, Georeference.
- **Native iOS guide:** https://docs.multiset.ai/multiset/native-support/ios-swift-native
- Other SDKs for cross-platform parity of naming and concepts: [android](https://github.com/MultiSet-AI/multiset-android-sdk) · [unity](https://github.com/MultiSet-AI/multiset-unity-sdk) · [quest](https://github.com/MultiSet-AI/multiset-quest-sdk) · [wearables](https://github.com/MultiSet-AI/wearable-vps-samples) · [unity-as-library](https://github.com/MultiSet-AI/unitysdk-as-library)
- **Existing production app** (avoid duplicating its role, and match its visual language): https://apps.apple.com/us/app/multiset/id6737130008

**Known-good auth contract** (confirmed from docs, still **[VERIFY]** the response shape at runtime):

```
POST https://api.multiset.ai/v1/m2m/token
Authorization: Basic base64("{clientId}:{clientSecret}")
→ { "token": "<JWT>", "expiresOn": "<ISO-8601>" }
```

Token lifetime is 30 minutes. Refresh proactively at ~25 minutes and on any `401`, with a single-flight guard so concurrent requests don't stampede the token endpoint.

---

## 5. `MultiSetKit` — networking and models

Build this first; everything else depends on it.

**Credential storage.** `clientId` and `clientSecret` go in the **Keychain** with `.whenUnlockedThisDeviceOnly`, never `UserDefaults`, never a plist, never source. Optionally gate retrieval behind Face ID. The JWT lives in memory only.

**Client shape.**

```swift
public protocol MultiSetAPI: Sendable {
    func authenticate(clientId: String, clientSecret: String) async throws -> AuthToken
    func maps() async throws -> [MapSummary]
    func map(code: String) async throws -> MapDetail
    func mapSets() async throws -> [MapSetSummary]
    func trackedObjects() async throws -> [TrackedObject]
    func query(_ request: LocalizationRequest) async throws -> LocalizationResult
    func queryObject(_ request: ObjectQueryRequest) async throws -> ObjectTrackingResult
}
```

Model every response as a `Codable` struct with explicit `CodingKeys`. **[VERIFY]** every field name against live responses — derive nothing from guesswork. Where a field's presence is uncertain, make it optional and handle absence in the UI rather than crashing.

**Error surface.** One `MultiSetError` enum: `.unauthorized`, `.rateLimited(retryAfter:)`, `.notLocalized`, `.network(URLError)`, `.server(status:message:)`, `.decoding(context:)`. Each case maps to a specific, actionable user-facing string. No "Something went wrong."

**Mock layer.** A `MockMultiSetAPI` conforming to the same protocol, backed by JSON fixtures, wired to SwiftUI previews and unit tests. This is what lets UI work proceed before credentials exist.

---

## 6. Design system — `MultiSetUI`

Derive the visual identity from https://www.multiset.ai/ and the existing App Store listing. **Match the brand; do not invent a new one.** Pull actual hex values from the site rather than approximating.

Requirements:

- **Tokens only.** Semantic names (`Color.msSurface`, `Color.msAccent`, `Spacing.md`) with light and dark variants. No literal hex or magic numbers in views.
- **Type scale** with named roles (`display`, `title`, `body`, `mono`). Use `SF Mono` for map codes, coordinates, pose values, and confidence numbers — this app shows a lot of engineering data and it should look like engineering data.
- **One signature element.** Pick a single memorable device tied to VPS — a confidence/pose readout treated as a first-class HUD component, for instance — and keep everything else quiet. Resist decorating every screen.
- **AR overlays are their own layer:** high contrast, legible against arbitrary camera feeds, thumb-reachable controls, never bottom-edge-adjacent (home indicator).
- **Quality floor, unannounced:** Dynamic Type to XXL, VoiceOver labels on every control, visible keyboard focus, `reduceMotion` respected, all touch targets ≥ 44 pt.

**Copy rules.** Active voice, sentence case, named by what the user controls. "Publish experience," not "Submit." An action keeps its verb through the whole flow — the button that says *Publish* produces a toast that says *Published*. Empty states are invitations with a button, not apologies. Errors state what happened and what to do next, in the interface's voice.

---

## 7. Parent app — screen specification

### 7.1 Onboarding (unauthenticated, fully functional)

Three swipeable cards, skippable, shown once. Lands on a **Home** tab that is genuinely useful with no account:

- **Try a demo** → the offline demos from §11
- **Scan a QR** → in-app scanner, opens any hosted experience
- **Enter a code** → manual slug entry for when a camera can't reach the QR
- **Explore the platform** → the Learn tab

Nothing here may be gated behind login. Gating the demo content triggers Guideline 5.1.1.

### 7.2 Sign in (optional, reachable from Home and Settings)

Fields: `Client ID`, `Client Secret` (secure entry, reveal toggle), plus a QR-scan path so a developer can scan credentials off the developer portal instead of typing 40 characters on glass.

Below the form:
- Link to https://developer.multiset.ai/credentials with the words "Get your credentials"
- One line explaining, in plain terms, that credentials are stored in the device Keychain and used only to reach the developer's own MultiSet account

On success: persist to Keychain, fetch maps and objects concurrently, land on **Library**. On `401`: "Those credentials weren't accepted. Check them in the developer portal." — not "Login failed."

Sign-out clears the Keychain entry and every cached response.

### 7.3 Library — Maps

Searchable, sortable list. Each row: map name, `mapCode` in mono, thumbnail or generated placeholder, status pill (processing / ready / failed), created date, and badges for georeferenced / has-MapSet / has-nav-graph.

**Map detail** — the developer's cockpit for one map:

- Header: name, code, version, scale, point count
- If georeferenced: a MapKit snapshot with the map origin pinned, plus lat/lon/heading in mono
- Tabs or sections:
  - **Overview** — metadata, source type (LiDAR scan / E57 / 3DGS / 360)
  - **Test localization** → launches the AR localizer against this map, with a live pose + confidence + latency HUD. This is the single most valuable screen in the app for a developer standing in their own building.
  - **POIs** — list, add, edit, delete points of interest with local-space coordinates
  - **Experiences** — hosted experiences for this map, each with its QR and stats
  - **Actions** — copy code, share, download map file, delete (with typed confirmation)

### 7.4 Library — Objects

Same shape for tracked objects: name, object code, thumbnail, model info, and a **Test tracking** action that opens the tracker with outline-mesh overlay. Mirror the SDK's `ARObjectTrackingView` rendering so behaviour is consistent with what developers see in the sample project.

### 7.5 Publish — hosting an experience

The bridge between the two halves of the app. A short form, not a wizard:

| Field | Notes |
|---|---|
| Name | Internal label |
| Mode | Localize / Navigate / Track (segmented) |
| Map or MapSet | Picker, filtered to ready status |
| Destination POI | Required for Navigate; picker from the map's POIs |
| Tracked object | Required for Track |
| Card title | Max ~30 chars — what the end user reads on the App Clip card |
| Card subtitle | Max ~50 chars |
| Accent colour + logo | Optional venue branding |
| Active | Toggle — kills the experience without reprinting the QR |

**On save:** POST to the broker, receive the slug and canonical URL, then show a **QR result screen**:

- The QR rendered large, generated locally via `CIFilter.qrCodeGenerator` at high error correction
- The full URL in mono, tappable to copy
- **Export as PNG** and **Export as PDF** at print resolution, with the card title set beneath the code and quiet-zone margins preserved — venue staff will print this and tape it to a wall
- **Share sheet**
- **Test on this device** — opens the parent app's own handler for the same URL, so the developer verifies the payload without needing a second phone
- A note that the Clip card's appearance is configured in App Store Connect, with a deep link to the relevant docs

Experiences list supports revoke, duplicate, and edit. Revoking must invalidate server-side — a printed QR is out in the world forever.

### 7.6 Showcase — 3D model AR sandbox

A small library of bundled USDZ models (parent app only, not the Clip) placed on a detected plane. Controls: scale, rotate on Y, material or colour variants, reset, and a photo capture that writes to the camera roll with permission. Keep it to 4–6 models, chosen to demonstrate occlusion and lighting rather than to be a showroom. This section exists to give the app standalone AR utility and to show the SDK's rendering quality — it should not sprawl.

### 7.7 Learn — platform and technology

Native SwiftUI content, not a `WKWebView` wrapper. A web view shell is a Guideline 4.2 risk and reads as filler.

Cards for each capability, each with a short native explainer, a looping muted video or image set, and a "Read more" link out to the web:

| Capability | Link |
|---|---|
| Visual Positioning System | https://multiset.ai/visual-positioning-system |
| Object Tracking | https://multiset.ai/object-tracking |
| Mapping | https://multiset.ai/mapping |
| E57 → VPS | https://multiset.ai/e57-to-vps |
| 3DGS → VPS | https://multiset.ai/3dgs-to-vps |
| 360 → VPS | https://multiset.ai/360-to-vps |

Plus:

- **SDKs** — one card per public repo (Unity, iOS, Android, Quest, wearables, Unity-as-library) with platform badge, one-line description, and a link. Fetch star counts and last-commit dates from the GitHub API with a cached fallback so the section degrades gracefully offline.
- **Recognition** — 🏆 Best Developer Tool, Auggie Awards, AWE USA 2026 ([source](https://www.awexr.com/blog/auggie-Award-Winners-at-AWE-USA-2026)); "Most Robust" ranking, AREA 2025 Enterprise VPS Report ([source](https://multiset.ai/post/multiset-ai-earns-most-robust-ranking-in-areas-2025-enterprise-visual-positioning-system-report))
- **Blog** — https://multiset.ai/blog-post
- **Community** — [Discord](https://discord.com/invite/pftwqThTxb) · [YouTube](https://www.youtube.com/@MultiSetAI) · [GitHub](https://github.com/MultiSet-AI) · [LinkedIn](https://www.linkedin.com/company/multiset-ai) · [X](https://x.com/multiset_ai) · [Instagram](https://www.instagram.com/multiset.ai/)

### 7.8 Settings

Account state, environment switcher (production / staging, debug builds only), cache size and clear, diagnostics log export, permission status with a jump to system Settings, and:

- Privacy Policy — https://multiset.ai/privacy-policy
- Terms of Use — https://multiset.ai/terms-of-use
- Contact — contact@multiset.ai
- Report a hosted experience → see §12.2
- App version, build, SDK version
- Footer: `© 2026 MultiSet AI · All rights reserved` and
  `28 Geary Street STE 650 Suite #371, San Francisco, California 94108, USA`

---

## 8. `MultiSetAR-Core` — the AR layer

One protocol, three modes, shared by both targets. This is the piece that makes the Clip small.

```swift
public enum ExperienceMode: String, Codable, Sendable {
    case localize, nav, track
}

public protocol ARExperience: AnyObject {
    func start(session: ARSession, manifest: ExperienceManifest) async throws
    func pause()
    func resume()
    func teardown()
    var state: AsyncStream<ARExperienceState> { get }
}
```

`ARExperienceState` drives all UI: `.initializing`, `.searching(hint:)`, `.localized(pose:confidence:)`, `.lost(since:)`, `.navigating(distanceRemaining:nextTurn:)`, `.arrived`, `.tracking(objectID:pose:)`, `.failed(MultiSetError)`.

**Localize.** Wrap the SDK's single-frame and multi-frame paths. Surface a live HUD: confidence, latency, frames submitted, ARKit tracking state. Show a clear "point your camera at the room, not the floor" coaching overlay during search — most localization failures are user-aim failures.

**Navigate.** After localization, load the nav graph from the manifest, run A* over it, render the path as a procedurally generated ribbon or chevron trail anchored to the map's coordinate frame. Include a next-turn banner, distance-to-destination, arrival state, and re-localization prompts when tracking drifts. **No bundled meshes** — build geometry in code.

**Track.** Object query + outline mesh overlay, matching `ARObjectTrackingView`.

**Cross-cutting behaviour** all three share: graceful handling of camera permission denial mid-session, thermal throttling (drop query frequency before dropping frames), backgrounding and return, and a persistent "Not localized yet" state that never looks like a hang. Every mode needs a visible escape hatch.

---

## 9. App Clip target

Keep it ruthlessly thin. The Clip is a launcher with three screens.

**Invocation flow:**

1. `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` → parse the incoming URL
2. Validate host is `clip.multiset.ai` and path matches `/e/{slug}` — reject anything else with a clear message
3. Fetch the manifest from the broker (no credentials involved)
4. Show a **branded intro card**: venue title, subtitle, what will happen, and a single primary button ("Start navigating" / "Start tracking"). This is where camera permission gets requested with context — never cold.
5. Run the matching `ARExperience`
6. On completion or exit, show a **soft upsell**: `App Store Overlay` for the full app, plus a "Done" that just closes. Never block the experience behind the overlay.

**Handle these cases explicitly** — each is a real failure mode:

| Case | Behaviour |
|---|---|
| Malformed or unknown slug | "This code isn't valid anymore." + contact link |
| Experience deactivated | "This experience has ended." |
| Map still processing | "This location isn't ready yet." |
| No network | Retry affordance, explain that VPS needs a connection |
| Camera denied | Explain why it's needed, offer Settings |
| Device lacks ARKit | Named requirement, not a crash |
| Session expired mid-use | Silent manifest refresh, one retry, then surface |

**Entitlements:** Associated Domains with `appclips:clip.multiset.ai`; the AASA file must be live at `https://clip.multiset.ai/.well-known/apple-app-site-association` before any invocation works.

**Test invocation before adding AR.** Use **Local Experiences** (Settings → Developer → Local Experience) to prove the URL → Clip → manifest chain with a hello-world build. Debugging AASA problems and the size budget simultaneously is miserable. This is the single best sequencing decision in the project.

---

## 10. Deep linking in the parent app

The parent must handle the same `clip.multiset.ai/e/{slug}` URLs — required by Apple, and it's how a developer tests a QR without a clean device.

Also register a custom scheme `multisetar://` for internal navigation (`multisetar://map/{code}`, `multisetar://experience/{slug}`). Route everything through one `DeepLinkRouter` shared between targets so behaviour can't diverge.

---

## 11. Demo modes — the App Store survival kit

Build these as first-class features, not test hooks. They're also genuinely useful to developers demoing indoors at a conference booth.

1. **Object tracking demo** — ships with a printable target (PDF export from within the app) that also works displayed on a laptop screen. This is the headline demo because it works anywhere, immediately, with no map.
2. **Synthetic navigation** — detect a floor plane, drop a pre-authored nav graph scaled to a small room, run the real pathfinding and the real path rendering. Same code path as production, no VPS call. Label it "Demo map" in the UI.
3. **Simulation-data localization** — feed a recorded frame sequence through the localization pipeline so a reviewer sees a genuine VPS result at a desk. **[VERIFY]** the [Simulation Data API](https://docs.multiset.ai/multiset/basics/rest-api-docs/simulation-data) and the Unity SDK's [Localization Simulation](https://docs.multiset.ai/multiset/unity-sdk/localization-simulation) — if an equivalent path exists on iOS, use it rather than building a parallel mechanism.
4. **Recorded walkthrough video** — a short real-site clip in the Learn tab, framed as context. Supporting evidence, never a substitute for interactive demos.

All four reachable from Home without an account, in two taps.

---

## 12. Compliance

### 12.1 Permissions

Purpose strings must be specific — generic ones draw rejections:

```
NSCameraUsageDescription
  MultiSet AR uses the camera to recognize your surroundings and
  position AR content accurately in the space around you.

NSLocationWhenInUseUsageDescription
  Location narrows down which mapped area you're in, so positioning
  is faster and more accurate.

NSPhotoLibraryAddUsageDescription
  Save AR screenshots to your photo library.
```

Ship a complete `PrivacyInfo.xcprivacy` and make App Store Connect data-collection answers match it exactly. Mismatches are a common rejection cause.

### 12.2 User-generated content — Guideline 1.2

Third parties host content that loads in your app. That makes this UGC, and Apple expects four things:

1. **Report mechanism** on every hosted experience — in the Clip's intro card and the parent's viewer
2. **A published moderation policy** you can point a reviewer to
3. **Reachable contact info** — contact@multiset.ai in-app
4. **Server-side kill switch** to disable a specific experience or a whole developer account

Build the kill switch regardless of Apple. You want it the first time someone publishes something they shouldn't.

### 12.3 Reviewer notes

Draft these in the repo as `REVIEW_NOTES.md` and keep them updated:

- Demo credentials for a populated test account
- A directly tappable invocation URL plus the QR as an attached image
- Step-by-step for reaching each offline demo
- One sentence stating that live VPS localization requires physical presence at a mapped site, which is exactly why the demos exist

Telling a reviewer the limitation before they discover it changes the outcome.

---

## 13. Testing

- **Unit:** URL parsing (including hostile inputs), manifest decoding, token refresh single-flighting, A* over nav graphs, coordinate transforms
- **Snapshot:** every screen in light and dark, at default and XXL Dynamic Type
- **Integration:** the full auth → maps → publish → resolve chain against mocks
- **Manual matrix:** iPhone SE (small screen, older chip), a current Pro, iOS 16 minimum and latest; each of the seven Clip failure cases in §9; QR scanning from a printed page at 0.5 m and 2 m, and from a screen
- **CI gates:** Clip size ≤ 13 MB uncompressed; no `clientSecret` string reachable from the Clip target (grep the build products, not just the source)

---

## 14. Phases

Stop for review at each boundary.

| Phase | Deliverable | Done when |
|---|---|---|
| **0** | Xcode project, both targets, three packages, design tokens, mock API, `ARCHITECTURE.md` documenting the broker contract | Both targets build and run; every screen has a preview backed by mocks |
| **1** | SDK integrated; **measure Clip binary size**; one localization session working against a real map | Size number is known and recorded. If over budget, escalate before continuing. |
| **2** | Auth, Keychain, Maps + Objects library, map detail, test-localization HUD | A developer can sign in and localize in their own building |
| **3** | Nav graph, POI authoring, `ARExperience` protocol with all three modes | All three modes run from the parent app |
| **4** | Clip target: Local Experience invocation, manifest fetch, intro card, mode dispatch, all seven failure cases | A QR on a printed page launches a working Clip |
| **5** | Publish flow, QR generation, PNG/PDF export, experiences list with revoke | Round trip: publish in app → print → scan → navigate |
| **6** | Learn tab, 3D showcase, Settings, all demo modes, `REVIEW_NOTES.md`, privacy manifest | Submission-ready |

---

## 15. Resolve these before Phase 3

Do not guess. Read docs, read the SDK, or ask.

1. Does the MultiSet platform store POIs and nav graphs, or does the app need its own store for experience metadata? This determines whether the broker is thin or owns a database.
2. Does the iOS SDK expose on-device localization, or is every query a round trip? Affects Clip size and offline behaviour.
3. What is the actual `mapCode` vs `mapSetCode` selection logic in the SDK, and can one session switch between them?
4. Current App Store Connect cap on registered advanced App Clip experiences per app — this bounds how many venues one app can serve. **[VERIFY] against live Apple docs; it has changed across iOS releases.**
5. Whether default-experience-plus-query-params gives enough per-venue card customization to avoid registering each venue individually. If yes, the cap in (4) stops mattering.
6. Rate limiting and abuse policy on broker-minted session tokens — per slug, per device, per hour.
