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
- `tools/`: `screenshots.sh` and `scenes/` (`make site-shots`), `shot.swift`, which crops a window screenshot to the window's edge and writes the WebP images the pages use, and `og-image.swift`, the link preview (see below).
- `appcast.xml`: Sparkle's update feed, which `make dist` writes and signs. Never edit it by hand (`docs/internal/Releasing.md`).
- `CNAME`: the custom domain. `.nojekyll`: Pages serves the files as they are.

The license page carries the text of the repository's `NOTICE` and links to `LICENSE`; keep them the same.

## Publishing

`.github/workflows/pages.yml` uploads this folder to Pages on every push to `main` that touches it. The site is live at https://getsilverbox.app, with a "Coming soon" banner until the first release (`docs/internal/Releasing.md`). The setup, done once:

1. Settings › Pages › Build and deployment › Source: **GitHub Actions**.
2. Settings › Pages › Custom domain: `getsilverbox.app`, then Enforce HTTPS once the certificate is issued.
3. At the DNS provider: `A` records for the apex at GitHub Pages' addresses (185.199.108.153, 185.199.109.153, 185.199.110.153, 185.199.111.153), and their `AAAA` records; optionally `www` as a `CNAME` to `silvercodestudio.github.io`. GitHub's "Managing a custom domain" page has the current list.

## Screenshots

Every screenshot on the page has a scene in `tools/scenes`, named as its images are. After the app's look changes, take them again:

```sh
make site-shots                            # every scene, light then dark
make site-shots SCENES='library details'   # some of them
make site-shots APPEARANCES=dark           # one appearance
LIBRARY=/Volumes/eXoDOS_ro make site-shots # another collection than yours
```

1. It builds the Debug app and starts it in front with the scene's launch arguments, on your own collections: the Ultima search with Ultima V selected (`library`), the welcome with no collection (`-noLibrary 1`), the inspector scrolled to the extras (`details`), the game info sheet (`game-info`), or Settings › Display & Sound (`display-sound`). The main window is 1320 × 840 points unless the scene names a `windowSize`.
2. Take a region screenshot (Shift-Command-4) a little larger than the main window, with desktop all around it, then quit the app (Command-Q; close a sheet first with Escape). For a scene with `"capture": "window"`, take a screenshot of that window alone instead: Shift-Command-4, Space, then Option-click it. Take them on a Retina display.
3. The script finds the new screenshot in the screenshot folder, keeps it in `build/site-shots`, and runs `shot.swift` on it (`--radius 36` for a region capture). Then the dark appearance, and the next scene.

It puts the app's settings back after each run, sets the page's `<img>` heights to the new images', and makes `og-image.jpg`, the link preview, again from the dark library (`tools/og-image.swift`). The captions and alt text stay as they are: check them when a screenshot shows something new. A scene file holds `arguments` (launch arguments, quoted as in a shell), and optionally `capture`, `widths` (default `2400,1200`), `radius` and `windowSize`.

### By hand

The tool finds the window's edge inside a capture, crops to it, and writes a 2400-wide and a 1200-wide WebP (JPEG when `cwebp`, from `brew install webp`, is missing):

```sh
swift docs/site/tools/shot.swift ~/Desktop/capture.png docs/site/images/library-dark --radius 36
```

`--rect X,Y,W,H` crops that rectangle instead, `--trim L,T,R,B` cuts more from each side, and `--widths 1200,600` writes smaller sizes. Make each capture in both appearances, name them `-dark` and `-light`, and write alt text that says what the screenshot shows. The page uses:

| Name | What it shows |
|---|---|
| `library` | The main window: the Ultima games in eXoDOS, Ultima V selected |
| `welcome` | The welcome screen, with every emulator found |
| `details` | Ultima V's inspector, scrolled to the manual and what came in the box (shown cropped to 4:3, right side) |
| `game-info` | Ultima V's game info sheet (Command-I) |
| `display-sound` | Settings › Display & Sound, at 1200 and 600 wide |

The current screenshots come from the design mockup and are older than the app; replace them after the UI polish, before the first release.
