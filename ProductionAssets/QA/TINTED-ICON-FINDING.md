# Finding: the tinted app icon collapses

The shipping `app-icon-tinted.png` loses every facet. iOS renders the tinted
variant by mapping a greyscale source onto the user's chosen colour, so the mark's
facets have to sit at clearly separated grey values. They don't.

Measured inside the mark (central disc, background excluded):

| Variant | Tonal distribution | Reads as |
|---|---|---|
| `app-icon-light.png` | 122 (82k px) · 60 (57k px) · 197 (47k px) | three distinct facet groups |
| `app-icon-tinted.png` | **26 (202k px)** · 243 (17k px) | a solid black hexagon |
| `app-icon-tinted-PROPOSAL.png` | 100 (83k px) · 67 (58k px) · 166 (49k px) | facets preserved |

92% of the shipping tinted mark sits at one near-black value. At 40 pt it is
indistinguishable from a generic hexagon icon, which is the rejection criterion in
`multiset-ar-asset-production-brief.md` §3.

## The proposal

`app-icon-tinted-PROPOSAL.png` is derived from the **light** variant by measuring
the mark's own luminance range (17…245) and stretching it into 60…235 — dark enough
to read, light enough that the facets stay separate under a tint. It reproduces the
light variant's three-group structure.

Regenerate with:

```sh
swift Scripts/propose-tinted-icon.swift \
    ProductionAssets/AppIcon/app-icon-light.png \
    ProductionAssets/AppIcon/app-icon-tinted.png
./Scripts/sync-app-icon.sh
```

**Not applied.** The icon is a designed asset, so replacing it is the designer's
call. Either take the proposal, or rework the tinted variant by hand — but it
should not ship as it stands.
