# getsilverbox.app

The website for Silverbox: static HTML and CSS, no build step. GitHub Pages serves this folder as https://getsilverbox.app.

One small script, `js/site.js`, runs the theme button (sun and moon, next to the GitHub mark) and the full-size image viewer. The pages work without it: they follow the system appearance, the button stays hidden, and a screenshot link opens the image itself. A theme chosen with the button is kept in `localStorage` only while it differs from the system's; a one-line script in each page's `<head>` applies it before the page draws.

## Preview

```sh
make site      # serves this folder at http://localhost:8001
```

Switch macOS between Light and Dark (System Settings › Appearance) to see both themes; the screenshots swap with the appearance.

## Files

- `index.html`: the home page. `privacy.html` and `license.html`: the privacy and license pages.
- `css/tokens.css`: the design tokens as CSS custom properties, from the Silverbox design system (the Claude Design site mockup). Dark is the base; light follows `prefers-color-scheme` (or `data-theme="light"` on `<html>`).
- `css/site.css`: the design system's components (`sb-` classes) and the page layout. Every color, radius, and font comes from a token.
- `js/site.js`: the theme button and the image viewer. Each screenshot is a `<picture>` inside `<a class="zoom">`: `href` is the full-size dark image, `data-light` the light one, and the light `<source>` carries `data-theme-light` so the script can follow the chosen theme.
- `images/`: the app icon (`icon.png`, `favicon.png`, `apple-touch-icon.png`, from the amber icon's flat PNG) and the screenshots, each in dark and light, at two widths for `srcset`.
- `tools/shot.swift`: crops a window screenshot to the window's edge and writes the WebP images the pages use (see below).
- `CNAME`: the custom domain. `.nojekyll`: Pages serves the files as they are.

The license page carries the text of the repository's `LICENSE`; keep the two the same.

## Publishing

`.github/workflows/pages.yml` uploads this folder to Pages on every push to `main` that touches it. Setup, once:

1. Settings › Pages › Build and deployment › Source: **GitHub Actions**.
2. Settings › Pages › Custom domain: `getsilverbox.app`, then Enforce HTTPS once the certificate is issued.
3. At the DNS provider: `A` records for the apex at GitHub Pages' addresses (185.199.108.153, 185.199.109.153, 185.199.110.153, 185.199.111.153), and their `AAAA` records; optionally `www` as a `CNAME` to `silvercodestudio.github.io`. GitHub's "Managing a custom domain" page has the current list.

## Screenshots

Capture the window with Shift-Command-4, then Space, then click the window (hold Option to leave out the shadow). The tool finds the window's edge inside the capture, crops to it, and writes a 2400-wide and a 1200-wide WebP (JPEG when `cwebp`, from `brew install webp`, is missing):

```sh
swift docs/site/tools/shot.swift ~/Desktop/capture.png docs/site/images/library-dark
```

Make each capture in both appearances, name them `-dark` and `-light`, and write alt text that says what the screenshot shows. The pages use:

| Name | What it shows |
|---|---|
| `library` | The main window: the Ultima games in eXoDOS, Ultima V selected |
| `welcome` | The welcome screen, with every emulator found |
| `details` | Ultima V's inspector, scrolled to the manual and what came in the box (shown cropped to 4:3, right side) |
| `game-info` | Ultima V's game info sheet (Command-I) |
| `display-sound` | Settings › Display & Sound, at 1200 and 600 wide: keep the tool's 1200 output and make the 600 one with `cwebp -resize 600 0` |

The current screenshots come from the design mockup and are older than the app; replace them before the site goes live.
