---
name: cosmos-color-palette
description: Applies the Cosmos visual color palette for UI, shaders, VFX, and branding decisions. Use when the user asks for color tweaks, theme changes, palette updates, visual polish, or requests consistent game colors.
---

# Cosmos Color Palette

Use this skill to keep color choices consistent across gameplay UI, shaders, effects, and promo visuals.

## Core palette

- `#000000`
- `#051427`
- `#530f1e`
- `#a44322`
- `#f8bc04`

## Preferred usage

- Use `#000000` as the deepest background/shadow base.
- Use `#051427` as the primary dark space/navy tone.
- Use `#530f1e` for deep accent contrast (warm shadow/accent).
- Use `#a44322` for mid warm highlight, UI emphasis, and glow transitions.
- Use `#f8bc04` for brightest highlight, focal accents, and important callouts.

## Application rules

1. Keep overall scenes dark-first (`#000000`, `#051427`) so warm tones pop.
2. Reserve `#f8bc04` for sparse highlights; avoid flooding full backgrounds with it.
3. For gradients, prefer cool-to-warm progression:
   - `#051427 -> #530f1e -> #a44322 -> #f8bc04`
4. If transparency is needed, adjust alpha only; keep hue consistent with nearest palette color.
5. When proposing new visuals, map every chosen color to the nearest palette color.

## Output format when asked for color recommendations

Return recommendations as:

```markdown
Palette selection:

- Background: <hex>
- Mid tone: <hex>
- Accent: <hex>
- Highlight: <hex>

Why:

- <1-3 short bullets>
```

## Additional resources

- Palette reference: [palette.md](palette.md)
