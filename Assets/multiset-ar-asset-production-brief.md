# Asset Production Brief — MultiSet AR (iOS + App Clip)

> **How to use this document**
> Third in the set, after `multiset-ar-ios-build-prompt.md` (architecture) and `multiset-ar-design-brief.md` (visual direction). Run the design brief first — the palette and type decisions it produces are inputs to almost everything here. Sections marked **[GEN]** contain image-generation prompts ready to paste. Sections marked **[CODE]** must not be generated as images.

---

## 1. Read this before generating anything

Image generation is the wrong tool for most of what this app needs. Getting that division right is the difference between a coherent app and a set of pretty pictures that don't match each other.

### Never generate these

| Asset | Why | Do instead |
|---|---|---|
| The MultiSet logo or wordmark | It exists. Generated approximations are trademark-adjacent garbage with wrong letterforms | Get the vector from the brand team, or extract the SVG from multiset.ai |
| UI icons (tabs, chevrons, actions) | Generated icon sets are inconsistent in weight, optical size, and stroke | **SF Symbols.** Free, Dynamic-Type aware, VoiceOver-labelled, and they match every other iOS app. Custom SF Symbols for the 3–4 genuinely domain-specific glyphs |
| AR overlays — path ribbons, arrows, markers, target reticles | Must be procedural geometry in the AR scene, and the App Clip has a 15 MB budget with **zero room for bundled 3D assets** | RealityKit meshes generated in code |
| Charts, graphs, data readouts | Live data | SwiftUI Canvas / Swift Charts |
| Gradients, scrims, blurs, borders | Generated as PNGs they bloat the bundle and break in dark mode | CSS-equivalent SwiftUI modifiers |
| Any image containing readable text | Diffusion models mangle text, and text in images can't localize or scale with Dynamic Type | Real text layered over the image |
| Identifiable faces | Model release / privacy exposure, and it dates the app | Hands, backs of heads, silhouettes, figures at distance |
| Third-party logos in scenes | Trademark. Generated warehouse scenes love inventing plausible-looking brand marks | Prompt them out (see negative prompt) and inspect every output |

### The App Clip gets essentially no image assets

Icon set only. Every pixel counts against 15 MB. Venue branding — logo, accent colour — streams from the experience manifest at runtime. Design the Clip's intro card so it looks intentional with *no* imagery at all, because that's the fallback when a venue provides none.

---

## 2. Global visual direction

Every generated image in this app shares one look. Establish it once, then hold it.

**Subject world.** Enterprise spatial computing: warehouses, airport terminals, factory floors, breweries, plant rooms. Reality capture: LiDAR sweeps, point clouds, E57 scans, 360° panos. Survey instrumentation: control points, benchmarks, tolerance callouts, registration marks. This is the tradition MultiSet's accuracy claims descend from, and it's a far richer well than sci-fi HUD imagery.

**Look.** Grounded and architectural, not futuristic. Real spaces with real materials — polished concrete, powder-coated steel racking, brushed aluminium, sodium and fluorescent lighting mixed with daylight. Digital elements read as *precise measurement laid over reality*, not as glowing magic. Think a surveyor's plan-view registration diagram more than a film's targeting display.

**Light.** Directional, single dominant source, honest shadows. Wide-angle but not fisheye. Slightly elevated eye level, as if standing.

**Colour.** Muted, desaturated environments so the accent — MultiSet's own, extracted from the brand — carries all the emphasis. One accent per image, used sparingly. Restraint here is what makes the set feel designed rather than assembled.

**Global negative prompt** — append to every generation:

```
no text, no words, no letters, no numbers, no logos, no brand marks,
no watermarks, no signage, no readable labels, no identifiable faces,
no sci-fi HUD, no corner brackets, no scanlines, no Tron grid floor,
no neon glow, no lens flare, no cyberpunk, no holographic rainbow,
no glassmorphism panels, no floating UI cards, no smartphone mockups,
no cluttered composition, no oversaturation, no vignette
```

**Consistency strategy.** Generate the App Clip card header (§5) first, iterate until it's genuinely good, then use it as a **style reference image** for every subsequent generation. Consistency across a set is the hard part of image generation, and a single locked anchor solves most of it. If your tool supports style references or seeds, lock them and record the values in the asset manifest.

---

## 3. App icon — design it, don't generate it **[CODE]**

The most important asset in the app and the one AI generation is worst at. It must read at 40 pt on a home screen, sit beside the existing MultiSet app as a sibling, and survive being tinted.

**Approach:** derive it from the brand mark. Take the existing MultiSet symbol and give it one AR-specific modification — a single idea, executed in vector. Candidate directions, pick one and commit:

- The brand mark as a **survey control point** — the mark centred in a registration cross
- The mark rendered as a **coordinate origin** — three axes converging, drawn with real geometric precision
- The mark **anchored to a plane** — the symbol with a subtle ground-plane relationship, showing the core idea of content pinned to space

Generation *is* useful for exploring these directions quickly. It is not useful for the final file. Rebuild the chosen direction as vector.

**Hard specs:**

- 1024×1024 PNG, **no alpha channel, no transparency, no baked rounded corners** — iOS masks it
- Three variants required on iOS 18+: **light, dark, and tinted**. Design the tinted variant deliberately — it's rendered from a single-colour treatment, so an icon relying on multi-colour contrast collapses. Test it.
- Legible at 40 pt, 60 pt, 76 pt, 1024 pt. Screenshot all four and look at them small.
- **App Clip icon:** same mark, no separate design. Apple applies its own Clip badge treatment; don't pre-badge it.

**Reject if:** more than two visual elements, any text, a gradient doing the heavy lifting, or indistinguishable from a generic AR app at 40 pt.

---

## 4. Onboarding illustrations **[GEN]** — 3 images

Three swipeable cards, shown once. Each pairs with a headline layered as real text — **do not generate text into these.**

**Format:** 1290×1290 px source (square, safely croppable), PNG. Light and dark variants each. Portrait-safe composition with the subject in the upper two thirds, since text sits below.

### 4.1 `onboarding-01-map` — "Your space, mapped"

```
A wide interior of a modern distribution warehouse, tall steel racking
in receding rows, polished concrete floor, high bay lighting mixed with
daylight from clerestory windows. Overlaid on the scene, a sparse field
of small precise measurement points traces the geometry of the shelving
and floor — thin, delicate, technical, like a surveyor's registration
diagram rather than a glowing effect. Points concentrated on structural
edges and corners, absent in open air. Desaturated concrete and steel
palette, one restrained accent colour on the measurement points only.
Architectural photography, directional light, honest shadows,
slightly elevated eye level, wide angle without distortion.
```

### 4.2 `onboarding-02-localize` — "The phone knows where it is"

```
Interior of an airport terminal concourse, polished stone floor,
structural columns, soft diffused daylight from a high glazed roof.
A single person seen from behind at mid-distance, holding a phone up at
chest height, walking. Faint precise geometric alignment marks converge
on the floor near their position — a registration cross and a small
set of concentric measurement rings, drawn thin and technical, indicating
an exact known position rather than a search. Restrained, architectural,
quiet. Muted stone and glass palette with a single accent colour on the
alignment marks. Natural light, real shadows, documentary framing.
```

### 4.3 `onboarding-03-guide` — "Follow the line"

```
A brewery production floor: stainless steel fermentation tanks in a row,
epoxy-coated concrete, industrial pendant lighting, pipework overhead.
A continuous slim path marker runs along the floor, curving between the
tanks and receding into depth — flat, precise, matte, laid onto the
concrete like painted floor marking rather than a glowing hologram.
It terminates at one tank in the middle distance with a simple
geometric destination mark. No text, no labels. Muted steel and
concrete palette, one accent colour on the path only.
Architectural interior photography, warm industrial light,
slightly elevated eye level.
```

**Dark variants:** regenerate with lower ambient light and the accent slightly raised in luminance — don't just darken the light version, the accent will die.

---

## 5. App Clip card header **[GEN]** — generate this first

The single highest-stakes image in the project. It's what a stranger sees on the App Clip card before anything installs — one image and two lines of text — and it's also the **style anchor** for every other generation.

**Spec:** 3000×2000 px (3:2), PNG, no text, no logo. Apple crops and overlays the title, subtitle, and action button, so keep the centre-bottom third visually calm.

```
An interior wayfinding moment, seen at human eye level: a wide corridor
in a modern industrial building, concrete floor, clean architectural
lines, natural light from one side. A slim continuous path marker runs
along the floor into the middle distance and turns out of frame,
rendered flat and matte like precise painted floor marking. Absolutely
no interface elements, no devices, no people. Calm, spacious,
confident. Muted palette of concrete grey, steel, and daylight, with a
single restrained accent colour on the path. Architectural photography,
soft directional light, generous negative space in the lower centre of
the frame.
```

**Iterate until this one is genuinely good** — it sets the standard for the set, and it's the product's first impression. Then lock the seed or save it as a style reference.

**Per-venue variants:** each venue can supply its own header. Provide a template and a 3:2 crop guide in the publish flow, plus this generic image as the default when they don't.

---

## 6. Learn tab capability cards **[GEN]** — 6 images

One per capability page, matching the language on each. **Format:** 1600×1000 px (16:10), PNG, dark-mode variant each. These sit behind or above real text, so keep them quiet.

Reuse the global direction and the style anchor. Per-image subjects:

| Asset | Page | Subject prompt core |
|---|---|---|
| `learn-vps` | [VPS](https://multiset.ai/visual-positioning-system) | A multi-floor atrium seen in section-like perspective; the same sparse precise measurement points across two visible levels, showing continuity of one coordinate system between floors |
| `learn-object-tracking` | [Object tracking](https://multiset.ai/object-tracking) | A single piece of industrial equipment — a pump skid or electrical cabinet — on a plant floor, with a thin precise outline traced exactly along its silhouette and edges, like a registration overlay, nothing filled or glowing |
| `learn-mapping` | [Mapping](https://multiset.ai/mapping) | A person seen from behind sweeping a handheld scanner across a warehouse aisle, with the swept volume suggested as a faint sparse point field trailing behind the motion |
| `learn-e57` | [E57 → VPS](https://multiset.ai/e57-to-vps) | A dense architectural point cloud of an interior, rendered in monochrome greys, with one region resolving into cleaner structured geometry — the transition legible left to right |
| `learn-3dgs` | [3DGS → VPS](https://multiset.ai/3dgs-to-vps) | A soft, slightly diffuse volumetric reconstruction of a room interior, edges blooming gently, resolving toward crisp geometry at one side. Painterly at the soft end, precise at the resolved end |
| `learn-360` | [360 → VPS](https://multiset.ai/360-to-vps) | An equirectangular panorama of an industrial interior, subtly curved, with faint precise registration marks distributed across it |

**SDK cards** (Unity, iOS, Android, Quest, wearables, Unity-as-library) get **no generated imagery** — use SF Symbols or simple vector platform glyphs on a tinted surface. Generated device renders look cheap and the platforms have their own brand assets.

---

## 7. Empty and error states **[CODE]**

Four states need illustration, and all four should be **drawn as SVG or SwiftUI shapes**, not generated. They must scale with Dynamic Type, tint with the accent, and work in both registers — generated raster illustrations do none of that.

| State | Idea |
|---|---|
| No maps yet | An empty registration grid with one control point placed — an invitation, not a void |
| No objects yet | The same grid, one outlined volume ghosted in |
| Not localized / searching | A registration cross with the alignment not yet converged. Must not read as a hang — pair with elapsed time and an escape hatch |
| Experience ended / invalid code | A registration mark, struck through cleanly. Neutral, not alarming |

Keep them geometric, thin-stroked, and consistent with the icon's construction. One visual family across all four.

---

## 8. Printable QR sheet template **[CODE]**

The physical artifact of the whole product — venue staff tape this to a wall. Build it as a **PDF generated in code**, not an image.

- A4 and US Letter, portrait
- QR at ≥ 100 mm square, high error correction, **quiet zone preserved** — the most common failure is a QR crowded to its edges
- The venue's card title beneath in large type, subtitle below it
- Vertical space for a venue logo, optional
- Small MultiSet attribution at the foot
- Vector throughout, pure black on white for the code itself. Never tint the QR modules; contrast is what makes it scan at 2 m

Test the output printed on paper at 0.5 m and 2 m, and displayed on a screen.

---

## 9. 3D showcase models — source, don't generate

The AR sandbox needs 4–6 USDZ models. Text-to-3D output is not production quality for AR — bad topology, broken UVs, wrong scale, no PBR discipline.

**Source instead:** Apple's Quick Look gallery, Sketchfab under permissive licences, Poly Haven, or commission them. Choose models that demonstrate what the SDK does well:

- One with genuine reflectivity, to show environment lighting
- One with fine geometric detail, to show occlusion against real surfaces
- One at furniture scale and one at equipment scale, to show accurate real-world sizing
- One with material variants, for the customization controls

**Per model:** ≤ 5 MB, real-world scale in metres, correct up-axis, baked PBR, LOD if the tool supports it. **Parent app only — none of this ships in the Clip.** Record the licence for every model in the manifest.

---

## 10. App Store assets

- **Screenshots:** 6.9" and 6.5" required. Use **official Apple device frames** — Apple has specific rules about how its hardware is depicted, and non-official frames get flagged. Real captures, not mockups. Caption text layered in design tooling, never generated.
  - Suggested sequence: AR navigation in a real space → localization instrument view → maps library → publish/QR moment → object tracking → App Clip card
- **App preview video:** 15–30 s, captured on device. Screen recording of an actual localization lock is more persuasive than any produced footage — the moment a map snaps on is the product.
- **App Clip card assets:** the header from §5, at every size App Store Connect asks for.

---

## 11. Export matrix

| Asset | Source size | Ships as | Variants | Budget |
|---|---|---|---|---|
| App icon | 1024² vector | Asset catalog, single size | light / dark / tinted | — |
| Onboarding ×3 | 1290² | @2x @3x HEIC | light / dark | ≤ 400 KB each |
| Clip card header | 3000×2000 | ASC upload only | — | ≤ 2 MB |
| Learn cards ×6 | 1600×1000 | @2x @3x HEIC | light / dark | ≤ 300 KB each |
| Empty states ×4 | SVG | Vector in asset catalog | tints with accent | ≤ 10 KB each |
| SDK/platform glyphs | SF Symbols or SVG | — | — | — |
| USDZ models ×5 | — | Parent bundle | — | ≤ 5 MB each |

**Format notes.** HEIC over PNG for photographic assets — meaningfully smaller at equivalent quality on iOS 16+. SVG or PDF vector for anything geometric. Enable **On-Demand Resources** for the USDZ models and the Learn imagery so first install stays lean.

**Naming:** `{surface}-{index}-{subject}-{variant}` → `onboarding-01-map-dark`, `learn-e57-light`. Consistent, sortable, greppable.

**Asset manifest.** Keep `ASSETS.md` in the repo recording, for each generated image: the exact prompt, the tool, the seed or style reference, the date, and the licence status of anything sourced. Regenerating a matching asset six months from now is impossible without this, and it's also your provenance record if anyone asks how the imagery was made.

---

## 12. QA checklist

- Every generated image inspected at 100% for invented text, garbled signage, phantom logos, and mangled hands. Diffusion models produce all four confidently.
- No identifiable faces in any output.
- Every image legible in both light and dark mode, in place, on a real device.
- App icon checked at 40 pt beside the existing MultiSet app, in all three variants.
- Clip card header checked with the title, subtitle, and action button overlaid — the crop is not yours to control.
- Clip target's asset catalog contains **only** the icon set. Grep the build products to confirm.
- Total app size before and after asset integration, recorded. If the delta surprises you, something is uncompressed.
- Printed QR sheet scans at 0.5 m and 2 m, on paper and on screen.
- Licences recorded for every sourced model and every reference image.

---

## Reference

**Brand** https://www.multiset.ai/ · **Existing app** https://apps.apple.com/us/app/multiset/id6737130008 · **Docs** https://docs.multiset.ai/multiset

**Capability pages for imagery direction** [VPS](https://multiset.ai/visual-positioning-system) · [Object tracking](https://multiset.ai/object-tracking) · [Mapping](https://multiset.ai/mapping) · [E57→VPS](https://multiset.ai/e57-to-vps) · [3DGS→VPS](https://multiset.ai/3dgs-to-vps) · [360→VPS](https://multiset.ai/360-to-vps)

© 2026 MultiSet AI · contact@multiset.ai
