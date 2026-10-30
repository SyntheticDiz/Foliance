# Foliance implementation and verification

30 October 2026. Version 1.0.0, build 2. Work is confined to this project; the original application and its user data were not modified by this work.

## Product decisions

Foliance is a free, general-use, English-only macOS PDF reader and is open source under MIT. Preserve the original app's shared styles, typography, layout and controls. The macOS toolbar explicitly suppresses automatic shared glass backgrounds to retain the original flat controls. The icon is a new corporate folded-page F monogram; its source and exact 1024-pixel bitmap are in Assets.

Overview is the default base analysis. Report, Project plan and Meeting notes add reviews of full source passages under Findings, Decisions, Actions, Costs, Deadlines, Risks and Context. Reading goals, optional reference documents and comparison criteria are propagated without treating source text as instructions. Quotes and user notes remain verbatim, including non-English source material. App-authored interface, analysis instructions and export labels are English only.

The independent bundle/preferences/sandbox identity is app.foliance.mac; portable work files use .foliance. There is no predecessor data, credential or settings migration. Work files preserve PDF bytes, results, profile, focus, reference/criteria, notes and reader state. Reopening work does not start AI requests. Recent files activate security-scoped bookmarks before checking access.

## AI connections

Apple Intelligence is the local default. Optional OpenAI API-key billing stores each user's key in its own non-synchronizing Keychain item. Optional Continue with ChatGPT uses OpenAI's documented free/open-source OAuth flow: loopback PKCE, state/nonce, issued-client registration, signed ID-token validation, explicit direct-use scope checks, refresh/revocation and account-specific model lists. ChatGPT registrations have separate Keychain records; only an opaque host identifier and active client identifier are in preferences.

Cloud content requires revocable versioned consent. Captured model identifiers retain API-key versus ChatGPT-plan billing through worker/orchestrator routing and model switches. Missing permission never selects another billing path. Responses requests are HTTPS, streamed and use store:false; this does not promise zero retention. The temporary callback listener binds only to 127.0.0.1. No developer API key or account is bundled, imported or used in tests.

## Verification

The final integrated offline suite passed: 5 core tests and 760 app tests registered, 66 optional/live/private-fixture tests skipped, 0 failures (699 executed). It includes token verification, callback/PKCE, separate account storage, consent, billing isolation, serialized Responses requests, English output labels and exact source preservation. The public export contains a smaller focused suite; inherited research probes are excluded.

Universal arm64/x86_64 release preview built successfully, with a strict ad-hoc signature, sandbox/file-bookmark entitlements, outbound networking plus loopback callback entitlement, English localization and privacy manifest. Release audit passed for identity, old branding, private filesystem paths and embedded API credentials. Native checks confirmed the flat toolbar, modern icon, English settings, separate cloud controls, recent-work opening, source search and local work saving. All native document checks used a clearly labeled fictional prepared fixture, not real AI output.

No live ChatGPT sign-in, live model-catalog retrieval or real AI request was performed. Actual account eligibility and end-to-end service access need a user-owned account validation before submission. Existing compiler/SDK deprecation warnings do not prevent the verified build.

## Public source, website and distribution

Public repository: https://github.com/SyntheticDiz/Foliance . Public site/support/privacy: https://syntheticdiz.github.io/Foliance/ . Static source is in SupportSite. Only audited source, assets, fictional sample and public metadata may be published. Exclude Submission.local.json, signing material, builds/caches, Verification and private documents. The source packager uses an explicit allowlist.

The expanded website was checked in a real browser: app-inspired controls/palette, fictional profile examples, keyboard navigation, support/privacy links and a 390-pixel responsive content viewport. Motion respects reduced-motion preferences. Publication retains the existing GitHub Pages URLs.

The clean public export includes all application source and focused, fictional-data tests. It compiled independently and passed 5 core plus 40 app tests. Inherited tests/probes referencing private research paths or political fixtures are excluded from public source and the distributable source archive; the full local regression suite remains in this development folder. The public export was separately checked for personal paths, old branding, private research paths and embedded credentials.

Remaining publisher prerequisites: application and installer distribution signing identities, explicit bundle-ID registration/provisioning profile, App Store Connect app record and publisher fields, accepted-size final screenshots, review access for optional account features, signed package validation/upload and Apple review. Team and public URLs are stored only in ignored AppStore/Submission.local.json. The preview is ad-hoc signed, not an App Store-signed release, and no submission has been made.

Capability limits: ordinary image-only PDFs need a searchable text layer before import; table extraction and AI interpretation require review; on-device analysis requires compatible Apple Intelligence hardware/model; external OpenAI plan/API limits apply.
