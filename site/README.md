# OrbitDock Marketing Site

Zero-dependency static site builder. No frameworks, no npm install — just Node.js.

## Quick start

```bash
# Build to site/dist/
npm run site:build

# Build + serve at localhost:3000
npm run site:dev

# Custom port
node site/build.js --serve --port 8080
```

If you are working from inside `site/`, you can use the local package scripts too:

```bash
npm run build
npm run dev
```

## How it works

Each page is a content-only HTML file with frontmatter. The build script injects that content into a shared layout, resolves partials (nav, footer), and copies static assets to `site/dist/`.

## File structure

```
site/
  build.js              # Build script
  src/
    layout.html         # Page shell (head, backgrounds, scripts)
    partials/
      nav.html          # Shared nav with active link markers
      footer.html       # Shared footer
    pages/
      index.html        # Each page = frontmatter + content
      about.html
      privacy.html
      support.html
      terms.html
    scripts/
      site.js           # Star field generator + scroll reveal
    styles.css          # All styles
  dist/                 # Built output (gitignored)
```

## Adding a page

Create `site/src/pages/your-page.html`:

```html
---
title: Your Page - OrbitDock
description: A short description for meta tags.
active: about
---

<section class="your-content">
  <h1>Hello</h1>
</section>
```

Run `npm run site:build` and it appears at `site/dist/your-page.html`.

## Cloudflare Pages

Recommended setup for this repo:

- Root directory: `site`
- Build command: `npm run build`
- Build output directory: `dist`

That setup keeps the Pages project focused on the marketing site instead of the repo root.
It also avoids the root-level `dist/` directory, which is used for release artifacts and is not the website.

If you prefer to keep the Pages project rooted at the repo root instead, use:

- Root directory: `(repo root)`
- Build command: `node site/build.js`
- Build output directory: `site/dist`

## Frontmatter fields

| Field | Required | Description |
|-------|----------|-------------|
| `title` | Yes | Page `<title>` |
| `description` | Yes | Meta description |
| `active` | No | Which nav link to highlight (`about`, `support`) |
| `ogTitle` | No | Open Graph title (index only) |
| `ogDescription` | No | Open Graph description (index only) |

## Template syntax

- `{{variable}}` — replaced with the frontmatter value (empty string if missing)
- `{{#if variable}}...{{/if}}` — conditional block, included only if the variable is truthy
- `{{> partial}}` — includes `src/partials/partial.html`
- `{{active:name}}` — in nav partial, resolves to `class="active"` when the page's `active` field matches
