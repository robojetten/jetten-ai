# jetten.ai

Pseudonymous, AI-co-authored policy briefs addressed to the Dutch cabinet.
See [/about/](https://jetten.ai/about/) for the editorial standard and how the site is written.

## Local development

```bash
# install hugo (macOS)
brew install hugo

# clone (after the GitHub robojetten/jetten-ai repo exists; see RUNBOOK.md)
git clone github-robojetten:robojetten/jetten-ai.git
cd jetten-ai

# install the pre-commit hook (identity-leak preflight)
./scripts/install-hooks.sh

# serve at http://localhost:1313/
hugo server --bind 127.0.0.1 --port 1313

# production build (output to ./public/)
hugo --minify
```

## Repository layout

- `content/` — markdown sources for every page.
  - `posts/manifesto/` — pinned bilingual manifesto.
  - `posts/european-solar-spine/` — the flagship policy brief.
  - `about/`, `contact/`, `timeline/`.
- `layouts/` — Hugo templates. `_default/` is the fallback; sectioned dirs (e.g. `posts/`, `timeline/`) override per-section.
- `assets/css/main.css` — single composed stylesheet, fingerprinted by Hugo at build time.
- `static/` — files copied verbatim into the site root: `CNAME`, `robots.txt`, favicon set, fonts, og-image.
- `scripts/preflight.sh` — identity-leak check; runs as pre-commit hook and inside GitHub Actions.
- `scripts/install-hooks.sh` — wires the preflight as a pre-commit hook (idempotent; safe to re-run).
- `.github/workflows/hugo.yaml` — CI: preflight → build → deploy to GitHub Pages.

## Deployment

Push to `main` triggers a build that runs:

1. Identity-leak preflight (blocks deploy on any match against the forbidden-string list, image C2PA/JUMBF metadata, or wrong git author).
2. Hugo build with `--minify` and the GitHub Pages base URL.
3. Deploy to GitHub Pages.

Custom domain `jetten.ai` is configured in repo Settings → Pages, with `enforce HTTPS` on.
DNS is fronted by Cloudflare (orange-cloud proxy) to hide the GitHub Pages origin from DNS lookups.

## Editorial standard

**The Pride Principle:** every post must be something we would be proud to put our real name on if the pseudonym is ever pierced. If publishing would cause embarrassment, it does not get published.

## License

Text and analyses on this site are © Robo Jetten and may be quoted with attribution. The site theme and code are MIT-licensed.
