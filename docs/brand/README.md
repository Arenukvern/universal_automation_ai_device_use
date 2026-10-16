# Brand assets

Visual identity for **universal automation device use**: multiple device classes
(desktop, mobile, embedded) unified by composable blocks, with warm dawn tones
and abstract **human + agent** figures collaborating (hopeful, not dystopian).
Aligns with [VISION.md](../VISION.md).

| Asset | Path |
| --- | --- |
| Icon (SVG) | [`assets/svg/icon.svg`](assets/svg/icon.svg) |
| Banner (SVG) | [`assets/svg/banner.svg`](assets/svg/banner.svg) |
| Icon 256 PNG | [`assets/png/icon-256.png`](assets/png/icon-256.png) |
| Icon 512 PNG | [`assets/png/icon-512.png`](assets/png/icon-512.png) |
| Banner 16×9 PNG | [`assets/png/banner-16x9.png`](assets/png/banner-16x9.png) |

Regenerate PNG exports after editing SVG:

```sh
rsvg-convert -w 256 -h 256 docs/brand/assets/svg/icon.svg -o docs/brand/assets/png/icon-256.png
rsvg-convert -w 512 -h 512 docs/brand/assets/svg/icon.svg -o docs/brand/assets/png/icon-512.png
rsvg-convert -w 1600 -h 400 docs/brand/assets/svg/banner.svg -o docs/brand/assets/png/banner-16x9.png
```
