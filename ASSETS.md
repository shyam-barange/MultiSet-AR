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

## Photographic imagery — `ProductionAssets/`

Produced to the direction in `Assets/multiset-ar-asset-production-brief.md` on
2026-08-19 with OpenAI's built-in image-generation tool. The tool did not expose
a reproducible seed. No third-party reference photography was used.

| | |
|---|---|
| Ships as | `ProductionAssets/MultiSetProductionAssets.xcassets`, in the **App target only** |
| Contents | 3 onboarding illustrations + 6 Learn capability cards, light and dark each |
| Format | HEIC, per the brief's format note |
| Onboarding | 1290² · `OnboardingMap`, `OnboardingLocalize`, `OnboardingGuide` |
| Learn | 1600×1000 · `LearnVPS`, `LearnObjectTracking`, `LearnMapping`, `LearnE57`, `Learn3DGS`, `Learn360` |
| Clip card header | `ProductionAssets/Optimized/Clip/clip-card-header.heic`, 3000×2000. **Uploaded to App Store Connect, never bundled** — the Clip's catalog stays at an icon set alone. |
| Style anchor | `ProductionAssets/Raster/Clip/clip-card-header-source.png` |
| Prompt record | `ProductionAssets/Prompts/final-prompts.md` records the final prompt set and edit chain; the TSV files map generator outputs |

Both view layers fall back to the geometric illustration family if a named image
is missing, so a dropped asset degrades instead of leaving a blank card.

### Compression results

| Group | Largest final file | Budget |
|---|---:|---:|
| Onboarding | 204,773 B | 400 KB each |
| Learn | 270,535 B | 300 KB each |
| Clip header | 338,414 B | 2 MB |

`ProductionAssets/Raster/` contains the full-resolution PNG masters. The HEIC
derivatives and appearance-aware catalog are the shipping copies. Moving the PNG
masters to Git LFS remains a repository-owner decision because that can rewrite
history.

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

- All 19 HEIC files decode as HEIF/HEVC still images at their specified dimensions.
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
