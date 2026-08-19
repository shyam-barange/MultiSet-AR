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

The repo also carries hand-authored SVGs for the same four empty states, from the
initial commit, in `Assets/empty-state-svg/`. They are kept as design source but
are **not** in either asset catalog: the `Canvas` implementation is parameterised
— the searching state converges as attempts accumulate, which a static SVG cannot
do — and it needs no catalog entry, which keeps the Clip's catalog to an icon set
alone. Swap to the SVGs if a designer prefers them; they would need adding to both
targets and marking as template-rendered to tint.

## Photographic imagery — `ProductionAssets/`

Produced to the direction in `Assets/multiset-ar-asset-production-brief.md`.

| | |
|---|---|
| Ships as | `ProductionAssets/MultiSetProductionAssets.xcassets`, in the **App target only** |
| Contents | 3 onboarding illustrations + 6 Learn capability cards, light and dark each |
| Format | HEIC, per the brief's format note |
| Onboarding | 1290² · `OnboardingMap`, `OnboardingLocalize`, `OnboardingGuide` |
| Learn | 16:10 · `LearnVPS`, `LearnObjectTracking`, `LearnMapping`, `LearnE57`, `Learn3DGS`, `Learn360` |
| Clip card header | `ProductionAssets/Optimized/Clip/clip-card-header.heic`, 3000×2000. **Uploaded to App Store Connect, never bundled** — the Clip's catalog stays at an icon set alone. |
| Provenance | `ProductionAssets/Prompts/*.tsv` records the generator output path per image |

Both view layers fall back to the geometric illustration family if a named image
is missing, so a dropped asset degrades instead of leaving a blank card.

### Repo size

`ProductionAssets/Raster/` is 99 MB of full-resolution source PNGs; everything
that ships is the 3.5 MB of HEIC in `Optimized/` and the asset catalog. The
rasters are tracked because the `Prompts/` TSVs point at paths outside the repo,
making these the only durable copy — but they will slow clones. **Recommend
moving `ProductionAssets/Raster/**` to Git LFS.** Not done here: converting
rewrites history, which is the repo owner's call.

`ProductionAssets/QA/` is empty; the brief's §12 checklist has not been run
against the final assets yet.

## App icon

| | |
|---|---|
| Ships from | `ProductionAssets/AppIcon/app-icon-{light,dark,tinted}.png` |
| Installed at | `App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-{Light,Dark,Tinted}-Production.png` |
| Spec | 1024², opaque, no alpha — verified with `sips -g hasAlpha` |
| Idea | The brand mark as a survey control point: the mark centred in a registration cross with tick terminals. Two elements, no text, no gradient carrying the design. |
| Clip icon | Same files. Apple applies its own Clip badge — not pre-badged. |

`Scripts/generate-app-icon.swift` builds the same idea from
`Assets/multiset_logo.png` and was used before the production icons arrived. It is
kept for exploring variants and is marked superseded in its header — **do not
regenerate over the production files.**

**Still to check at 40 pt** beside the existing MultiSet app, in all three
variants, per the brief's §12 checklist.

## Colour

Extracted from the dashboard's own CSS
(`Multiset-Dashboard/multiset-dashboard/src/app/globals.css`), not approximated:

| Token | Light | Dark |
|---|---|---|
| accent | `#7C3AED` | `#A78BFA` |
| surface | `#FFFFFF` | `#1E1B2E` |
| background | `#F5F5F9` | `#141220` |
| text primary | `#111028` | `#F4F2FA` |
| border | `#E0DEE8` | `#2E2A45` |

The SDK sample app uses `#7B2CBF`; the dashboard's `#7C3AED` is canonical here.

## Type

SF Pro and SF Mono only. No bundled faces: the Clip's byte budget forbids them,
and shipping brand fonts in the app but not the Clip would make the two look like
different products. SF also gets Dynamic Type and VoiceOver metrics right for
free. The brand carries through colour, spacing, and the mono treatment of
engineering data.

## Not produced yet

| Asset | Blocker |
|---|---|
| USDZ showcase models (4–6) | Need licensed sources; generated 3D is not production quality for AR. Record each licence here. |
| App Store screenshots and preview video | Need a real mapped site and official Apple device frames. |
