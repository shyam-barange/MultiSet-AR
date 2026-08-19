# Final image-generation prompts

Tool: OpenAI built-in `image_gen`  
Date: 2026-08-19  
Seed: not exposed by the built-in tool  
Style reference: `ProductionAssets/Raster/Clip/clip-card-header-source.png`  

Every generation included this negative constraint, with asset-specific additions:

```text
no text, no words, no letters, no numbers, no logos, no brand marks,
no watermarks, no signage, no readable labels, no identifiable faces,
no sci-fi HUD, no corner brackets, no scanlines, no Tron grid floor,
no neon glow, no lens flare, no cyberpunk, no holographic rainbow,
no glassmorphism panels, no floating UI cards, no smartphone mockups,
no cluttered composition, no oversaturation, no vignette
```

## Clip header

```text
Use case: photorealistic-natural
Asset type: MultiSet AR App Clip card header, final production artwork, 3:2 landscape
Primary request: An interior wayfinding moment at human eye level in a modern industrial building. A wide clean corridor with a concrete floor, precise architectural lines, and natural daylight entering from one side. A single slim continuous path marker in exact MultiSet purple #7B2CBF runs flat and matte along the floor into the middle distance, makes one clean turn, and continues out of frame. The path must look like precise painted floor marking, never luminous or holographic.
Composition/framing: 3:2 landscape, wide-angle architectural photography without fisheye distortion. Calm and spacious. Preserve generous low-detail negative space in the centre-bottom third for App Clip title, subtitle, and action button overlays.
Lighting/mood: soft directional natural light, one dominant source, honest realistic shadows, confident and restrained.
Color palette: muted and desaturated concrete grey, powder-coated steel, and cool daylight; only the path uses #7B2CBF.
Materials/textures: believable polished concrete, brushed or powder-coated metal, subtle real-world wear; crisp photographic detail.
Constraints: no interface elements, no devices, no people. [negative constraint]
```

Final edit:

```text
Change only the purple floor-route composition. Move the entire route out of the centre-bottom overlay-safe zone: it should enter from the lower-right edge within the outermost right third, stay near that right third as it recedes, then make one clean turn in the middle distance and exit out of frame. Keep the architecture, camera, palette, exact #7B2CBF, materials, and lighting unchanged.
```

## Onboarding

All are square, portrait-safe, grounded architectural photography with the technical subject in the upper two thirds and a quiet lower region for real UI text.

### Light

- `onboarding-01-map-light`: modern distribution warehouse, receding steel racking, polished concrete, mixed high-bay light and clerestory daylight; sparse #7B2CBF survey points adhere only to structural edges, corners, and planes; no people.
- `onboarding-02-localize-light`: bright airport terminal concourse; one anonymous adult from behind holding an unbranded phone naturally; thin #7B2CBF registration cross and concentric rings converge on the floor at the known position.
- `onboarding-03-guide-light`: brewery production floor with stainless fermentation tanks; a single flat matte #7B2CBF floor route curves between tanks and terminates at one precise geometric destination mark.

### Dark

The corresponding subject prompt was repeated with:

```text
Dark-mode artwork generated as a distinct low-ambient-light scene, not a darkened light image. Raise the purple technical accent luminance to #A85BE8 so it stays legible, but keep it matte and restrained.
```

The warehouse uses evening high-bay light and blue-hour clerestories; the terminal is after dusk; the brewery is a controlled night-shift scene. All preserve real material detail and honest shadows.

## Learn cards

Shared block:

```text
Input images: Image 1 is the locked MultiSet AR style reference for architectural realism, muted materials, directional light, sparse technical overlays, exact accent use, and restrained finish only.
Style/medium: grounded architectural photography and precise reality-capture visualization, never futuristic.
Composition/framing: 16:10 landscape capability-card artwork, clear subject, quiet edges and enough low-detail space for adjacent real UI text.
Color palette: muted desaturated greys and real materials; exact MultiSet purple #7B2CBF is the only accent.
[negative constraint]
```

### Light subjects

- `learn-vps-light`: large two-level atrium in believable section-like oblique perspective, one continuous sparse measurement coordinate field across both floors.
- `learn-object-tracking-light`: one unbranded industrial pump skid at precise three-quarter view with one exact hairline registration outline following its silhouette and important edges.
- `learn-mapping-light`: anonymous back-view operator sweeping a compact unbranded scanner across a warehouse aisle, leaving a sparse surface-adhering measurement point trail.
- `learn-e57-light`: one interior transitioning left-to-right from dense monochrome point cloud into clean structured architecture, with restrained control points at the boundary.
- `learn-3dgs-light`: one room transitioning from soft diffuse Gaussian splats on the left into crisp physical geometry on the right.
- `learn-360-light`: wide equirectangular-style industrial panorama with subtle curvature and faint registration marks fixed to real junctions.

Final corrections:

```text
learn-vps-light: Remove every person and human figure and reconstruct the vacated architecture naturally; change only people removal.
learn-mapping-light: Remove every sticker, shipping label, barcode, printed mark, and label-like rectangle from all cartons; make the scanner face plain, dark, and unlit; change nothing else.
learn-3dgs-light: Remove the thick purple floor route and reconstruct the concrete, then add exactly four tiny matte #7B2CBF registration points at crisp column-floor and ceiling-column junctions, with no lines.
```

### Dark subjects

The shared block replaced the colour line with:

```text
Dark-mode treatment: render a distinct low-ambient-light environment, not a darkened light image. Retain material detail in shadows and raise the technical accent to luminous-enough matte purple #A85BE8 without glow.
```

- `learn-vps-dark`: completely empty two-level atrium after dusk with one continuous coordinate field; absolutely no people.
- `learn-object-tracking-dark`: low-lit black pump skid with exact #A85BE8 registration outline.
- `learn-mapping-dark`: anonymous back-view operator, plain unlabelled cartons, blank scanner face, sparse #A85BE8 surface points.
- `learn-e57-dark`: dense monochrome survey point cloud resolving into structured geometry with restrained boundary points.
- `learn-3dgs-dark`: low-lit diffuse Gaussian splats resolving into crisp geometry; absolutely no route, stripe, arrow, or path.
- `learn-360-dark`: low-lit equirectangular-style panorama with restrained #A85BE8 marks fixed to architectural junctions.

All generated images are original and used no third-party reference photography. The supplied MultiSet logo was used only for deterministic icon construction, not as an image-generation input.
