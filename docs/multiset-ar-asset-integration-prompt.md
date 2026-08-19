# Asset Integration Prompt — MultiSet AR (Xcode)

> **How to use this document**
> Fourth in the set, after the build prompt, design brief, and asset production brief. Paste as the opening prompt to a coding agent working in the existing `MultiSetAR` Xcode project. **Complete Phase A and report before modifying the project file** — several decisions below depend on what the audit finds.

---

## 1. What exists

26 production assets have been generated and staged under `ProductionAssets/` in the project root, plus partial copies already placed in target asset catalogs. They are not yet wired into code.

```
ProductionAssets/
├─ Optimized/
│  ├─ Clip/clip-card-header.heic
│  ├─ Onboarding/onboarding-0{1,2,3}-{map,localize,guide}-{light,dark}.heic   (6)
│  └─ Learn/learn-{vps,object-tracking,mapping,e57,3dgs,360}-{light,dark}.heic (12)
├─ AppIcon/app-icon-{light,dark,tinted}.png
├─ Vector/EmptyStates/{empty-no-maps,empty-no-objects,state-searching,state-experience-ended}.svg
├─ Raster/{Clip,Onboarding,Learn}/…                    # PNG masters + -source.png + v1/v2/v3 history
├─ MultiSetProductionAssets.xcassets                    # 18 HEIC already installed here
├─ QA/                                                  # icon previews
└─ Prompts/final-prompts.md

Assets/empty-state-svg/                                 # duplicate SVG copies
App/Resources/Assets.xcassets/AppIcon.appiconset/       # 3 installed icon PNGs
Clip/Assets.xcassets/AppIcon.appiconset/                # 3 installed icon PNGs
ASSETS.md
```

---

## 2. Non-negotiables

Five things that will go wrong if not handled explicitly. Each is easy to get right now and expensive to fix after integration.

### 2.1 The Clip gets the icon set and nothing else

`ProductionAssets/` currently sits in the project root as a sibling of both targets. If it's added as a folder reference, or if `MultiSetProductionAssets.xcassets` is added to both targets' membership, the App Clip inherits 18 HEIC images plus PNG masters plus refinement history and **blows the 15 MB budget immediately.**

The Clip's `Assets.xcassets` contains `AppIcon.appiconset` and nothing more. `clip-card-header.heic` is an **App Store Connect upload, not a bundled resource** — it must not appear in any target.

### 2.2 Light/dark are appearance variants, not two named images

The naive integration is:

```swift
// WRONG
Image(colorScheme == .dark ? "onboarding-01-map-dark" : "onboarding-01-map-light")
```

This duplicates logic at every call site, breaks when a view isn't observing `colorScheme`, and fails inside `UIImageView` bridges and widgets.

**Correct:** one image set named `onboarding-01-map`, with the light file in the **Any** appearance slot and the dark file in the **Dark** slot. Then `Image("onboarding-01-map")` resolves automatically everywhere, including in snapshots and in `UIImage(named:)`. Apply to all 9 pairs (3 onboarding + 6 learn).

The existing `MultiSetProductionAssets.xcassets` was populated by a tool — **[VERIFY]** whether it created 18 separate image sets or 9 appearance-paired sets. If it's 18, restructure. Report which before proceeding.

### 2.3 Working files never reach the bundle

`-source.png`, `-v1/-v2/-v3`, `Raster/`, `QA/`, `Prompts/`, and `ASSETS.md` are provenance and working files. They belong in version control and **not** in Copy Bundle Resources. Add `ProductionAssets/` to the project as a **group with files added individually where needed**, or keep it entirely outside the Xcode project and reference only the catalogs. Never a folder reference with target membership.

### 2.4 Bundle resolution across packages

The build prompt puts the design system in a local `MultiSetUI` package and features in the `App/` target. **Assets in the app target are invisible to views defined in a package** — `Image("x")` inside `MultiSetUI` looks in `Bundle.module`, finds nothing, renders a blank.

Decide and document one rule:

- **Option A (recommended):** content assets (onboarding, learn) live in the **app target** catalog and are only referenced from views in `App/Features/`. Package views take images as parameters.
- **Option B:** assets live in `MultiSetUI/Sources/MultiSetUI/Resources/` and every reference uses `Image("x", bundle: .module)`.

Empty-state SVGs are used by both targets and both layers → they go in a shared package (`MultiSetUI`) with `bundle: .module`, and `MultiSetUI` must be a dependency of the Clip target. Confirm the Clip's SVG cost is negligible (it will be — see §5.2).

### 2.5 Single source of truth for the icon

There are now three copies of each icon: the master in `ProductionAssets/AppIcon/`, and installed copies in two appiconsets. That's guaranteed drift.

Treat `ProductionAssets/AppIcon/app-icon-*.png` as the master and the appiconset copies as **generated output**. Add `Scripts/sync-app-icon.sh` that copies masters into both appiconsets and rewrites nothing else, and note in `ASSETS.md` that the appiconset copies must never be edited directly.

---

## 3. Phase A — audit and report, do not modify

Produce a short report covering:

1. **Catalog structure:** does `MultiSetProductionAssets.xcassets` use appearance-paired image sets or separate light/dark sets? List the actual `Contents.json` structure for one onboarding asset.
2. **HEIC decode:** confirm each HEIC opens and reports expected dimensions. Run `sips -g pixelWidth -g pixelHeight -g format` across all 19. Flag anything that isn't actually HEIF, is 0 bytes, or is unexpectedly sized.
3. **Scale factors:** the files appear to be single-resolution. Confirm pixel dimensions and decide per set whether to configure **Single Scale** or supply @2x/@3x. Report the source dimensions so the decision is informed rather than guessed.
4. **Icon Contents.json:** does `AppIcon.appiconset` in each target use the iOS 18 single-size-with-appearances format (one 1024 entry per appearance) or the legacy multi-size format? Confirm no alpha channel on any of the three PNGs — `sips -g hasAlpha`. Alpha in an app icon is a hard App Store rejection.
5. **SVG duplication:** diff `ProductionAssets/Vector/EmptyStates/` against `Assets/empty-state-svg/`. Report whether they're identical, then propose one canonical location and deletion of the other.
6. **Current target membership:** list what each target currently compiles, and flag anything under `ProductionAssets/` that is already a member of the Clip.
7. **Baseline sizes:** record current `.app` size for both targets, and the Clip's uncompressed size, *before* integration. Everything after is measured against this.

Stop here and report.

---

## 4. Phase B — canonical layout

Restructure to:

```
App/Resources/Assets.xcassets/
├─ AppIcon.appiconset/                    # generated from masters
├─ Onboarding/
│  ├─ onboarding-01-map.imageset/         # Any + Dark
│  ├─ onboarding-02-localize.imageset/
│  └─ onboarding-03-guide.imageset/
└─ Learn/
   ├─ learn-vps.imageset/                 # Any + Dark
   ├─ learn-object-tracking.imageset/
   ├─ learn-mapping.imageset/
   ├─ learn-e57.imageset/
   ├─ learn-3dgs.imageset/
   └─ learn-360.imageset/

Packages/MultiSetUI/Sources/MultiSetUI/Resources/StateArt.xcassets/
├─ empty-no-maps.imageset/                # SVG, template, preserve vector
├─ empty-no-objects.imageset/
├─ state-searching.imageset/
└─ state-experience-ended.imageset/

Clip/Assets.xcassets/
└─ AppIcon.appiconset/                    # only this
```

Retire `ProductionAssets/MultiSetProductionAssets.xcassets` once its contents are folded into the app target catalog — a second catalog with an ambiguous name invites the exact target-membership mistake in §2.1. Keep `ProductionAssets/` as an un-compiled staging and provenance directory.

Add to `.gitignore`: nothing from `ProductionAssets/` — this is deliberate. The masters and prompts are worth keeping in history. Just keep them out of *build* membership.

---

## 5. Phase C — catalog authoring

### 5.1 Raster image sets (9 sets)

Per set: name without the `-light`/`-dark` suffix, light file in **Any Appearance**, dark file in **Dark Appearance**, and the scale configuration determined in Phase A.

**[VERIFY] the HEIC-in-catalog path.** Asset catalogs re-encode on compile, and HEIF sources have historically produced inconsistent results depending on toolchain version. Build once, then:

- Inspect the compiled `Assets.car` size (`assetutil --info` on the built product)
- Render each image on a device or simulator in both appearances and confirm no artifacting, no colour shift, and correct orientation

If HEIC misbehaves, fall back to the PNG masters in `ProductionAssets/Raster/` and let the catalog compressor handle it — a slightly larger `Assets.car` is better than a subtly wrong image. Report which path was taken.

### 5.2 SVG state illustrations (4 sets)

These need three settings, and all three matter:

| Setting | Value | Why |
|---|---|---|
| Scales | **Single Scale** | Required for SVG; otherwise Xcode expects raster variants |
| Preserve Vector Data | **On** | Without it the SVG rasterizes at its intrinsic size and blurs when scaled up by Dynamic Type |
| Render As | **Template Image** | So they tint with the accent colour, including the venue accent injected in the Clip |

Then in code they take `.foregroundStyle()` like an SF Symbol. Verify each SVG has no hardcoded fills that survive template rendering — if a fill is baked, template mode will flatten it to a silhouette and the illustration will look broken. Inspect all four rendered at 3× the base size.

### 5.3 App icon

Use the iOS 18 format: one 1024×1024 entry each for `any`, `dark`, and `tinted` appearance. Confirm no alpha on all three. Run the sync script rather than hand-copying.

The tinted variant is the one that fails silently — it renders from a single-colour treatment, so verify it on a device with a tinted home screen, not just in the catalog preview.

---

## 6. Phase D — typed accessors

No stringly-typed image names in view code. Generate or hand-write a small accessor layer in `MultiSetUI`:

```swift
public enum AppImage: String {
    case onboardingMap      = "onboarding-01-map"
    case onboardingLocalize = "onboarding-02-localize"
    case onboardingGuide    = "onboarding-03-guide"
}

public enum LearnImage: String, CaseIterable {
    case vps            = "learn-vps"
    case objectTracking = "learn-object-tracking"
    case mapping        = "learn-mapping"
    case e57            = "learn-e57"
    case gaussianSplat  = "learn-3dgs"
    case panorama       = "learn-360"
}

public enum StateArt: String {
    case noMaps           = "empty-no-maps"
    case noObjects        = "empty-no-objects"
    case searching        = "state-searching"
    case experienceEnded  = "state-experience-ended"
}
```

Each with an `image` property that resolves against the correct bundle per the §2.4 decision. Add a unit test that iterates every case and asserts the asset loads — this catches a renamed or unmembered asset at test time instead of as a blank rectangle in a demo.

---

## 7. Phase E — wire into views

**Onboarding.** Three cards, one image each, headline and body as real text below. Images are decorative — the headline carries the meaning — so mark them `.accessibilityHidden(true)` rather than inventing alt text that duplicates the headline.

**Learn cards.** Map each `LearnImage` case to its capability card. Aspect ratio 16:10, `.aspectRatio(contentMode: .fill)` with a clip, so the card layout doesn't shift if a future asset is a different size.

**Empty and status states.** Wire `StateArt` into the four states from the design brief. `state-searching` is the important one: it appears over the AR camera feed during localization, so it needs the template tint plus a scrim or stroke to stay legible over arbitrary video, and it must be paired with an elapsed-time cue and an escape hatch. An illustration alone reads as a hang.

**Clip intro card.** Uses `state-searching` and the venue's manifest branding only. **No bundled imagery.** Confirm it looks intentional when a venue supplies no logo and no accent — that's the common case.

---

## 8. Phase F — On-Demand Resources

Tag the 6 Learn image sets as ODR under a `learn-content` tag, `Initial install tags` excluded, `Prefetched` on. The Learn tab is not first-run critical, and this keeps ~12 images out of the initial download. Handle the fetch with a visible loading state and a graceful failure — an ODR request can fail offline.

Do not put onboarding or state art in ODR. Both are needed on first launch, possibly before network.

---

## 9. Phase G — size gates

Re-measure against the Phase A baseline and record both numbers in `ASSETS.md`.

Add CI gates:

1. **Clip uncompressed ≤ 13 MB.** Fail the build above it.
2. **No content assets in the Clip.** Assert the Clip's compiled `Assets.car` contains only the icon set — `assetutil --info` on the Clip product, grep for any `onboarding-`/`learn-` name.
3. **No working files bundled.** Assert nothing matching `-source`, `-v[0-9]`, or `.svg` source files appears in either `.app`.
4. **Icon alpha check.** Fail if any appiconset PNG reports `hasAlpha: yes`.

Gate 2 is the one that matters most — it's the regression that costs a week when discovered at submission instead of now.

---

## 10. Phase H — verification checklist

- Every one of the 9 raster sets renders correctly in light and dark, on device, at the size it's actually used
- All 4 SVGs scale cleanly to 3× without blurring and tint correctly via `.foregroundStyle()`
- App icon checked at 40 pt beside the existing MultiSet app, in light, dark, and tinted
- App Clip icon renders with Apple's Clip treatment applied, not double-badged
- Snapshot tests pass in both appearances at default and XXL Dynamic Type
- Asset-loading unit test passes for every enum case
- Clip size gate passes with headroom recorded
- `ASSETS.md` updated: final catalog locations, the HEIC-vs-PNG decision from §5.1, the bundle-resolution rule from §2.4, and a note that appiconset copies are generated
- `clip-card-header.heic` confirmed **absent** from both build products and noted in `ASSETS.md` as an App Store Connect upload

---

## 11. Still outstanding

Not produced yet, tracked so they don't get forgotten:

- **Printable QR sheet** — code-generated PDF, not an asset. A4 + Letter, QR ≥ 100 mm with quiet zone preserved.
- **3D showcase models** — 4–6 USDZ, sourced or commissioned, not generated. Parent app only, ODR-tagged, licences recorded.
- **App Store screenshots** — 6.9" and 6.5", official Apple device frames, real captures.
- **App preview video** — a real localization lock, captured on device.
- **App Clip card upload** — `clip-card-header.heic` into App Store Connect at every requested size, with title and subtitle overlaid and the crop verified.

---

© 2026 MultiSet AI · contact@multiset.ai
