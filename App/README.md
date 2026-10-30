# Foliance

Foliance is a native macOS PDF reader for understanding reports, project plans and meeting papers while keeping original source passages in view. Version **1.0.0**, build **3**.

## Use

Open one PDF with selectable text. The app reads text, layout and tables, then starts on-device analysis when Apple Intelligence is available. You can read and search the document while processing continues. Ordinary image-only scans need a searchable text layer before import; table OCR is specialized and remains reviewable.

Choose **Overview**, **Report**, **Project plan** or **Meeting notes**. Overview uses the base document analysis; the other profiles add a review of complete source passages under findings, decisions, actions, costs, deadlines, risks and context. Add a **Reading goal** to guide the explanation without discarding source material. An optional **Reference document** and comparison criteria can be configured in Settings.

The workbench keeps PDF pages beside summaries and findings. Follow a finding to its source, read the full passage, ask a question, add notes or keep selected passages. Local search covers the document and available work. Export a PDF brief, or save a `.foliance` work document containing the original PDF, results, focus, selected profile, reference document and annotations. Reopening work does not start AI requests.

AI interpretations can omit or misread information. A matched quotation confirms its location, not the correctness of every explanation. Check important amounts, conditions and conclusions against the original PDF.

## Requirements and privacy

- macOS 26 or later. Apple Intelligence requires compatible Apple silicon, enabled Apple Intelligence and its downloaded model.
- Reading, local search and saved results remain available when AI is unavailable.
- Apple Intelligence is the default. Optional OpenAI API analysis requires each user’s own API key, compatible model access, separate API billing and explicit document-sharing consent. **Continue with ChatGPT** also supports eligible ChatGPT plans through OpenAI’s official open-source OAuth flow, with account-specific models and plan/credit usage limits. There is no automatic cloud fallback.
- OpenAI keys are stored only in Foliance’s non-synchronizing Keychain entry. They are excluded from work files, exports and preferences. No credentials are imported from another app.
- OpenAI requests send task content directly to OpenAI over HTTPS. Responses storage is disabled; this does not disable OpenAI abuse-monitoring retention. See the bundled and public privacy policy.
- The independent `app.foliance.mac` identity has its own preferences and sandbox container. File access is limited to user-selected files and security-scoped bookmarks; networking is outbound except for the temporary OAuth callback bound to 127.0.0.1.
- The interface, new analysis and app-authored export labels are English only. Original quotations and user-entered text remain unchanged; saved results retain their existing text.

## Build and verify

Use a recent Xcode with the macOS 26+ SDK and Swift 6.4 toolchain or later.

```sh
bash scripts/test.sh
bash build-app.sh preview
```

The preview build is `dist/preview/Foliance.app`. It is sandboxed and ad-hoc signed for local verification; it is not an App Store distribution signature. To check both architectures locally, set `FOLIANCE_UNIVERSAL=1` when building the preview.

The release builder packages the icon asset catalog, privacy manifest, local policy and third-party notices, then checks identity, sandbox entitlements and absence of obsolete branding, private filesystem paths and API keys. No private signing material belongs in this project.

See [distribution instructions](AppStore/Distribution.md), [App Store listing](AppStore/Listing.md) and [current verification status](HANDOFF.md).

## Public website

- [Website](https://syntheticdiz.github.io/Foliance/)
- [Support](https://syntheticdiz.github.io/Foliance/support.html)
- [Privacy](https://syntheticdiz.github.io/Foliance/privacy.html)
- [Public website repository](https://github.com/SyntheticDiz/Foliance)

`SupportSite/` contains the website sources. The public repository contains the static website at its root and the approved, MIT-licensed application source under `App/`. The initial 230-file application export was verified byte for byte before publication; the source packager maintains an explicit public-test allowlist for subsequent updates. Private research fixtures, local submission settings, signing material, personal documents and credentials are excluded.

## Project layout

- `Sources/FolianceApp/`: SwiftUI reader, extraction, source-grounded analysis, work files, search and export.
- `Sources/FolianceCore/`: general document cues and core analysis.
- `Sources/NativeSearchSupport/`: vendored search dependencies.
- `Tests/`: offline regressions and opt-in rendering/live probes.
- `Config/`: app identity, sandbox entitlements and required-reason API privacy manifest.
- `Assets/`: original Foliance icon artwork.
- `AppStore/`: sample PDF, policy, metadata, review notes and distribution instructions.
- `scripts/`: build support, release audit, signing-profile validation and publisher preflight.

Legacy internal review/model identifiers remain in the implementation for stable data structures. Internal legacy model identifiers are retained for data compatibility; visible choices are Apple Intelligence, OpenAI API key and ChatGPT plan. Missing credentials, plan permission or document-sharing consent fail closed. Captured model identifiers preserve the selected billing path throughout an operation. Release prompts and profiles are general-purpose.

## License

Foliance is free and open source under the MIT License. Third-party components retain their licenses in `ThirdPartyLicenses/`. App Store distribution does not imply that OpenAI usage is unlimited or that Apple has approved this build.
