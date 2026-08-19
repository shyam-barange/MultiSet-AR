# Asset manifest

Provenance for every asset that ships, per
`Assets/multiset-ar-asset-production-brief.md` §11. Regenerating a matching asset
later is impossible without this.

## Generated in code, no files

Per the brief, these are drawn at runtime rather than bundled — they scale with
Dynamic Type, tint with the accent, cost no bundle bytes, and are the only way
the App Clip can afford them.

| Asset | Where | Notes |
|---|---|---|
| Empty and error states (4) | `MultiSetUI/Illustrations/MSIllustration.swift` | Survey registration grid family: no maps, no objects, searching, invalidated |
| Localization heatmap | `MultiSetUI/Components/LocalizationHeatmap.swift` | SwiftUI `Canvas` over `/v1/account/analytics/heatmap` |
| Pose readout | `MultiSetUI/Components/PoseReadout.swift` | The signature component |
| Path ribbon and chevrons | `MultiSetARCore/Rendering/PathRibbon.swift` | Procedural `MeshResource` |
| POI markers, object outlines, origin gizmo | `MultiSetARCore/Rendering/MarkerGeometry.swift` | Procedural. The POI ring is a ring of boxes, not a cylinder — `generateCylinder` is iOS 18+ and the floor is iOS 16 |
| Printable QR sheet | `App/Support/QRCode.swift` | Vector PDF, A4 and US Letter, quiet zone preserved, ≥100 mm code |
| Printable demo target | `App/Support/QRCode.swift` | Vector PDF; asymmetric corner blocks so orientation resolves, not just position |
| All UI icons | throughout | SF Symbols only |

The repo also carries hand-authored SVGs for the same four empty states in
`Assets/empty-state-svg/` and `ProductionAssets/Vector/EmptyStates/`. They are
kept as design source but are **not** in either shipping asset catalog: the
`Canvas` implementation is parameterised — the searching state converges as
attempts accumulate — and it costs no catalog bytes.

## Where each asset lives

One rule, so a reference never resolves against the wrong bundle:

| Kind | Catalog | Bundle | Referenced from |
|---|---|---|---|
| Home, Onboarding, Learn imagery | `App/Resources/Assets.xcassets/{Home,Onboarding,Learn}/` | app target | `App/Features/` only |
| State illustrations | `Packages/MultiSetUI/…/Resources/StateArt.xcassets` | `Bundle.module` | anywhere, incl. the Clip |
| App icon | both targets' `AppIcon.appiconset` | app + Clip | — |

Assets in a target are invisible to views defined in a package, so anything both
the app and the Clip render has to live in `MultiSetUI`. Everything is reached
through the typed accessors in
`MultiSetUI/Tokens/AssetCatalog.swift` — `HomeImage`, `OnboardingImage`, `LearnImage`,
`StateArt` — never by string. `AssetCatalogTests` iterates every case and asserts
it loads, which catches a rename or a missing target membership at test time
instead of as a blank rectangle in a demo.

There is exactly one catalog per target. A second catalog with an ambiguous name
was retired because it invited the one-click mistake of adding it to both
targets' membership, which pushes 14 MB of content imagery into the Clip.

## Photographic imagery

Produced to the direction in `Assets/multiset-ar-asset-production-brief.md`.

| | |
|---|---|
| Home | 1536×1024 · `home-spatial-hero` |
| Onboarding | 1290² · `onboarding-01-map`, `-02-localize`, `-03-guide` |
| Learn | 1600×1000 · `learn-vps`, `-object-tracking`, `-mapping`, `-e57`, `-3dgs`, `-360` |
| Format | HEIC, single scale. Home uses one adaptable composition; Onboarding and Learn use light in **Any** + dark in **Dark** on one image set. |
| Clip card header | `ProductionAssets/Optimized/Clip/clip-card-header.heic`, 3000×2000. **App Store Connect upload, never bundled** — verified absent from both build products by `Scripts/check-bundled-assets.sh`. |
| Provenance | `ProductionAssets/Prompts/` |

Light and dark are appearance variants of one named set, not two named images, so
`OnboardingImage.map.image` resolves correctly everywhere — including in
`UIImage(named:)` bridges — without any view consulting `colorScheme`.

### HEIC vs PNG — measured, not assumed

The integration brief asked to verify the HEIC-in-catalog path and fall back to
the PNG masters if it misbehaved. It does not misbehave, and the fallback would be
worse:

| Source | `Assets.car` for 2 sets | Encodings emitted |
|---|---|---|
| **HEIC** (shipping) | **4.8 MB** | HEIF + RGB555/lzfse |
| PNG masters | 6.5 MB | ARGB only, no HEIF path |

The catalog emits two representations per image: the original HEIF (3.5 MB across
all 18) plus an RGB555 + lzfse fallback (17.8 MB). `ASSETCATALOG_COMPILER_OPTIMIZATION`
set to `space` or `time` changes neither.

RGB555 is 15-bit colour, which would band on these gradients — so quality was
checked rather than assumed. Distinct colour levels in the rendered image measured
**R=132 G=131 B=129**; RGB555 would cap each channel at 32. iOS renders the HEIF
representation, and the RGB555 entries are unused weight rather than a quality
path.

### On-Demand Resources

The six Learn sets carry `on-demand-resource-tags: ["learn-content"]`. Nothing on
first launch needs them, and they are most of the catalog:

| | Before ODR | After ODR |
|---|---|---|
| App `.app` (Release, device) | 31 MB | **18 MB** |
| Main `Assets.car` | 21 MB | **7.4 MB** |
| `learn-content.assetpack` | — | 14 MB, fetched on demand |

Onboarding and the state art stay in the bundle: both are needed immediately,
possibly before there is a network.

**A fetch can fail, so failure is a first-class state.** The Learn cards fall back
to text-only and show a notice with a retry, verified in both configurations.
Whether the artwork draws is decided by the asset itself (`isFullyLoaded`), not by
the loader's state — a tagged asset leaves a small stub in the main catalog, so
`UIImage(named:)` succeeding is not proof the pack arrived, and a build with the
tags removed must still show its bundled images.

**Simulator caveat:** a bare `xcodebuild` + `simctl install` cannot serve the asset
pack, so the Learn tab shows the fallback. Running from Xcode, TestFlight, or the
App Store resolves it. This is expected, not a defect.

## State illustrations

The four SVGs from `ProductionAssets/Vector/EmptyStates/` ship in
`MultiSetUI/Resources/StateArt.xcassets`, each configured **Single Scale**,
**Preserve Vector Data**, and **Template Image** — so they scale with Dynamic Type
without blurring and take `.foregroundStyle()`, including the venue accent the
Clip injects from its manifest. `AssetCatalogTests` asserts the template rendering
mode, because losing it makes every tint silently ineffective.

Inspected for baked fills before switching to template mode: three carry
`fill="#000"` and four `fill="none"`, all of which template rendering replaces
cleanly.

Two copies exist by design: `ProductionAssets/Vector/EmptyStates/` is the master,
and `MultiSetUI/Resources/StateArt.xcassets/` is the shipping copy. A third copy
under `Assets/` was removed.

`state-searching` is also drawn procedurally in
`MSIllustration.searching(progress:)`, and the AR coaching overlay uses that
version rather than the vector — it converges as attempts accumulate, which a
static asset cannot do, and it appears over a camera feed where an unchanging
illustration reads as a hang. The vector is used for every static presentation.

## App icon

| | |
|---|---|
| Ships from | `ProductionAssets/AppIcon/app-icon-{light,dark,tinted}.png` |
| Installed at | `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-{Light,Dark,Tinted}-Production.png` |
| Spec | 1024², opaque, no alpha — verified with ImageIO |
| Idea | The existing MultiSet mark as a survey control point: the mark centred in a precise registration cross with tick terminals. Two elements, no text, no baked corners. |
| Tinted | Deliberate single-colour mark treatment so it does not rely on multicolour contrast |
| Clip icon | Same files. Apple applies its own Clip badge — not pre-badged. |

`Scripts/generate-app-icon.swift` builds the same idea from
`Assets/multiset_logo.png` and is retained only for exploring variants. Do not
regenerate over the production files.

Pixel-scale inspection files for 40, 60, and 76 px are in `ProductionAssets/QA/`.
The remaining manual check is comparison beside the existing MultiSet app on a
real Home Screen.

## Colour

Extracted from the dashboard's CSS
(`Multiset-Dashboard/multiset-dashboard/src/app/globals.css`):

| Token | Light | Dark |
|---|---|---|
| accent | `#7C3AED` | `#A78BFA` |
| surface | `#FFFFFF` | `#1E1B2E` |
| background | `#F5F5F9` | `#141220` |
| text primary | `#111028` | `#F4F2FA` |
| border | `#E0DEE8` | `#2E2A45` |

The UI uses the dashboard's canonical `#7C3AED`. The photographic measurement
overlays use `#7B2CBF`, sampled from the supplied logo, with `#A85BE8` in dark
imagery so the technical layer survives low ambient light.

## Type

SF Pro and SF Mono only. No bundled faces: the Clip's byte budget forbids them,
and shipping brand fonts in the app but not the Clip would make the two look like
different products. SF also gets Dynamic Type and VoiceOver metrics right for
free. The brand carries through colour, spacing, and the mono treatment of
engineering data.

## Validation completed

- All 20 HEIC files decode as HEIF/HEVC still images at their specified dimensions.
- Every compressed image is within its production byte budget.
- The parent-app and standalone production catalogs compile successfully with `actool`.
- The app icon variants are 1024×1024 RGB PNGs without alpha.
- The Clip catalog contains no generated photographic raster assets.
- The four SVG design sources are 418–520 bytes each, far below the 10 KB limit.
- An unsigned generic-device build of the parent app and embedded App Clip succeeds.

## Not produced yet

| Asset | Blocker |
|---|---|
| USDZ showcase models (4–6) | Need licensed sources; generated 3D is not production quality for AR. Record each licence here. |
| App Store screenshots and preview video | Need a real mapped site and official Apple device frames. |


## Unused assets

| Asset | Status |
|---|---|
| `ProductionAssets/Optimized/Clip/clip-card-header.heic` | Correct — an App Store Connect upload, deliberately in no target. Still to be uploaded. |
| `Assets/logo.png` (2736×732, alpha) | The horizontal mark + wordmark lockup. **Not yet used anywhere in the UI.** |
| `Assets/multiSet_logo_white.jpg` (1024², no alpha) | White treatment of the mark. No current use; a JPEG without alpha is hard to place over anything. |
| `Assets/multiset_logo.png` (2048²) | Source for the superseded icon generator only. |

Everything else produced is wired: 1 Home hero, 3 onboarding sets, 6 Learn sets,
4 state illustrations, and the app icon in both targets.
