# Foliance implementation and release status

30 October 2026. Version 1.0.0, build 3. Work is confined to this fork; the original application and its data were not changed.

## Product and interface

Foliance is a free, MIT-licensed macOS PDF reader for reports, project plans and meeting papers. The independent bundle/preferences/sandbox identity is app.foliance.mac; work documents use .foliance. It does not migrate another application's settings, documents or credentials.

The interface, tutorial, newly generated explanations and app-authored export labels are English. The build 3 audit replaced missed overview headings, analysis/progress states, extraction notices, recovery and recent-file errors, selection-summary messages, generated table explanations and glossary-origin labels at their source. Dates use an English locale. Original document quotations, user notes and saved analysis text remain verbatim; legacy encoded values stay compatible. Regression tests cover untranslated UI/error templates and preservation of source text.

Keep the original shared typography, controls, cards and layout. The toolbar suppresses automatic shared glass backgrounds. The navy folded-page F artwork remains unchanged. The final builder declares Foliance.icns as the single system icon, removes the competing asset-name selector and removes the running-app override. The compiled AppIcon catalog retains its 1024-pixel store image; the release audit checks both resources.

Overview is the base profile; Report, Project plan and Meeting notes add source-linked review. Reading goals, optional reference documents and criteria guide analysis without treating source content as instructions. Work files preserve the source PDF, results, focus, profile, notes, reference, selected passages and reader state. Reopening work starts no AI request.

## AI and privacy

Apple Intelligence is the local default. OpenAI API-key billing and eligible ChatGPT-plan usage are separate optional routes with versioned, revocable document-sharing consent and separate non-synchronizing Keychain entries. The official free/open-source OAuth flow uses loopback PKCE, state/nonce, signed ID-token validation, issued clients and explicit plan-usage scope checks. Account model catalogs and reasoning options are authoritative. Captured model identifiers preserve billing and orchestrator/worker roles; missing credentials, permission or consent never select a different provider or billing route.

Requests use HTTPS directly to OpenAI with Responses storage disabled; abuse-monitoring retention still applies. The sandbox permits user-selected read/write files, scoped bookmarks, outbound networking and a temporary OAuth callback listener bound only to 127.0.0.1. No credentials or private signing material are bundled. Verification triggered no live AI/document requests or account sign-in.

## Signing and builds

The user accepted Apple's updated Developer Program License Agreement and explicitly approved creating both distribution certificates. Xcode created valid Apple Distribution and Mac Installer Distribution identities. The explicit app ID is registered, and the downloaded Mac App Store distribution profile matches the app, team and application certificate. Certificates/profile expire 30 October 2027. Private keys remain in Keychain; only fingerprints and the external profile path are recorded in ignored AppStore/Submission.local.json. No private keys were exported.

The builder reads explicit environment values before ignored local settings. Store mode creates a universal arm64/x86_64 application and signed installer package; preview mode creates an ad-hoc local runnable build. The final build 3 signed universal package passed signing/profile validation, strict signature verification and the icon/privacy/branding/path audit (log /private/tmp/foliance-build3-store-final.log). Both Mach-O slices declare minimum macOS 26.0. The package is dist/Foliance-1.0.0.pkg. No package has been uploaded or submitted.

## Verification

The full offline suite passed: 771 tests registered, 66 optional/live/private-fixture tests skipped, zero failures (705 executed), log /private/tmp/foliance-build3-tests-verified.log. A final focused run after date/icon/provider-label changes passed 83 registered tests, 6 skipped, zero failures, log /private/tmp/foliance-build3-final-focused.log.

A fresh native process verified English Document overview, Analysis status, model details, Reading agenda and Coverage check. Verification/english-overview-status-build3.png records these sections. The user-owned open fictional Sample.pdf work was preserved through the app's Save action as Verification/Sample-before-English-update.foliance before relaunch. Source/model contents were not regenerated. Native Finder inspection was not approved, so default-icon verification relies on bundle declarations/resource checks until a permitted native check is available.

## Public source and remaining release steps

Repository: https://github.com/SyntheticDiz/Foliance . Website: https://syntheticdiz.github.io/Foliance/ with support.html and privacy.html. The expanded app-inspired website is deployed; root static files and App/ application source are kept separate.

The initial audited 230-file source export was explicitly approved and published in commit a68e5f435061a4cc1933920404eefb2daf665126. Its exact ZIP is preserved as dist/Foliance-1.0.0-build2-approved-source.zip. The current build 3 source export contains 234 files and compiled independently with all 51 public tests passing (log /private/tmp/foliance-build3-public-tests.log). New source exports must use scripts/package-source.py's public test allowlist. Exclude local submission settings, signing material, build caches, Verification, private research probes and personal documents.

Remaining: App Store Connect app record and publisher/listing/privacy questionnaire fields, accepted-size final screenshots, validation of optional ChatGPT account access with a user-owned account, signed package validation/upload and Apple review. Verification captures are not automatically valid App Store screenshots. A successful build/signature audit does not promise App Store acceptance.
