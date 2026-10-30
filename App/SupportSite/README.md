# Foliance public website

This folder contains the buildless static website for Foliance: home, support, and privacy pages, a shared responsive stylesheet, a small progressive-enhancement script, and the SVG brand mark.

The site is hosted with GitHub Pages at:

- https://syntheticdiz.github.io/Foliance/
- https://syntheticdiz.github.io/Foliance/support.html
- https://syntheticdiz.github.io/Foliance/privacy.html

## Preview locally

From the project root, run any local static HTTP server, for example:

```sh
python3 -m http.server 8000 --directory SupportSite
```

Then open `http://localhost:8000/`. No package manager, build step, remote font, image service, analytics, or tracking code is required.

## Publish

The public GitHub repository contains only these static website files. Configure GitHub Pages to serve the repository root from its publishing branch. Keep application source, signing material, account credentials, local submission settings, and build output out of that repository. After editing the public policy or support text, verify every page link and keep the privacy policy’s effective date accurate.

Foliance is preparing for its first release. Do not add a download or App Store link until one exists. Do not include private PDFs, API keys, sign-in tokens, personal information, build artifacts, or private signing data on the public site.
