# Mac App Store screenshots

Three native screenshots are currently present and uploaded/confirmed in App Store Connect: `01-overview.png`, `02-findings.png`, and `03-selection-notes.png`. Each is 2560 × 1600 pixels (3 of 10 available slots).

Place any additional final native screenshots in this folder as PNG files. The preflight accepts one to ten PNGs at these exact Mac display sizes:

- 1280 × 800
- 1440 × 900
- 2560 × 1600
- 2880 × 1800

The strict `python3 scripts/preflight-store.py` check requires at least one PNG, validates its PNG structure and image data, and rejects dimensions outside this list. `build-app.sh store` uses `--allow-missing-screenshots` so signing can be prepared before captures exist; that option only permits screenshots to be absent. It does not waive checks for any PNG that is present. This local capture and validation pipeline supports PNG files only.

For a 2560 × 1600 capture on a 2× display, build and launch the preview with the screenshot-only window sizing enabled:

```sh
FOLIANCE_SCREENSHOT_CAPTURE=1 bash build-app.sh preview
```

This sizes the main reader window to 1280 × 800 points after it attaches. The flag is embedded only in this opt-in preview build and is never included in a store build. A normal preview build has no capture sizing.

Screenshots must show the actual Foliance interface and accurate, reviewable content. The fictional selectable-text source `AppStore/Sample.pdf` is available for captures. The capture option changes only the window size: it does not create mock interface content or send documents to an AI provider. Do not include private documents, credentials, test overlays, fabricated findings, or unsupported claims. Review each image at full size before adding it here.
