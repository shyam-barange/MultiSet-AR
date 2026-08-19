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

## App icon

| | |
|---|---|
| Source | `Assets/multiset_logo.png` (2048², the brand mark) |
| Generator | `Scripts/generate-app-icon.swift` |
| Command | `swift Scripts/generate-app-icon.swift Assets/multiset_logo.png App/Resources/Assets.xcassets/AppIcon.appiconset` |
| Output | `AppIcon-Light.png`, `AppIcon-Dark.png`, `AppIcon-Tinted.png` — 1024², opaque, no alpha |
| Idea | The brand mark as a survey control point: mark centred in a registration cross and ring. Two elements, no text, no gradient carrying the design. |
| Tinted variant | Pre-flattened to luminance with a lift, so the facets stay distinguishable when iOS renders it single-colour |
| Clip icon | Same files. Apple applies its own Clip badge — not pre-badged. |

**Reviewed at 40 pt:** the mark reads clearly; the cross and ring recede almost
entirely. That is the intended trade — the brand mark is what must be
recognisable at small sizes, and the registration treatment is a large-size
refinement. Worth a designer's eye before submission.

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
| Onboarding illustrations (3) | Currently the geometric illustration family. The brief's photographic direction needs a locked style anchor first. |
| App Clip card header | Needs iteration to a genuinely good result — it is the product's first impression and the style anchor for everything else. |
| Learn capability cards (6) | Should follow the locked style anchor. |
| USDZ showcase models (4–6) | Need licensed sources; generated 3D is not production quality for AR. Record each licence here. |
| App Store screenshots and preview video | Need a real mapped site and official Apple device frames. |
