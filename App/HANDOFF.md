# Foliance implementation and release status

30 October 2026. Version 1.0.0, build 4. Current build 4 status below supersedes the historical build 3 records. Work is confined to this fork; the original application and its data were not changed.

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

## Final publication and local verification

Build 3 public source was published to main in commit e5388f1d9c715a59e235ef3d5993b9224b966ef2. All 234 App/ files were read back and matched the source ZIP's Git blob hashes and modes; website-root files were unchanged. The ZIP SHA-256 is 0fb4c1ebacf14e0b94cd68c3143f2908e5fc8254dcdf31758dd435424c0b50ac. The signed package SHA-256 is 63173742421c2357f57641758d63c33a2c85675f36474ac2425d104eb04a338a. This publication record is local release bookkeeping added after the frozen export.

Final preview rebuild passed the same icon/privacy/branding audit. Refreshed only the preview app's LaunchServices registration. The pinned Dock path was confirmed to point to this preview, and the initial/runtime icon artwork itself was preserved. A fresh native process reopened the saved work with English overview/status and the corrected ChatGPT-plan online badge. Verification/english-overview-status-build3.png contains the final status capture. A resize attempt left the window at 2560×1680, so this is still verification material, not an accepted-size App Store screenshot. Finder control was not approved, and the Dock surface could not be inspected; do not claim a visual Finder/Dock comparison was performed.


## Build 4 — saved sessions and App Store setup

ChatGPT sessions restore the selected account/client/host from Foliance’s own non-synchronizing Keychain without opening a browser. Settings can retry a temporary read failure. Provider readiness waits for restoration. Expiring sessions serialize refresh requests and save rotated tokens as an atomic account record. A temporary Keychain write failure retains the rotated record in actor memory and retries storage before another request, preventing reuse of a consumed refresh token. Pending memory cannot survive quitting before Keychain accepts the write; no plaintext fallback is used. Switching accounts cannot be undone by a late refresh, and sign-out clears/supersedes pending tokens. OpenAI can require sign-in again after expiry or revocation. Tests use injected memory storage and URLProtocol, not real credentials or live AI.

New glossary lookup code uses English Wikipedia; saved legacy article identifiers remain readable. Article/author-history attribution, CC BY-SA 4.0 and a modification notice apply to the Wikipedia text and adapted explanation in the UI and exported PDFs; original user PDFs and notes keep their own terms. The automated lookup service currently has no production callsite; the active glossary offers explicit external browser links. Do not claim automatic Wikipedia data collection.

The final offline full suite passed with native Vision/AppKit access: 780 registered, 66 skipped, 714 executed, zero failures (log /private/tmp/foliance-build4-all-tests-native.log). A restricted sandbox attempt produced Vision nilError failures and a runner signal; targeted OCR/PDF tests and the full native run passed without code changes. The independent public-source staging suite passed 72 registered, 1 skipped, 71 executed, zero failures (log /private/tmp/foliance-build4-public-check/public-offline-tests.log). No live AI or account login was performed.

A signed universal build 4 package passed the profile, signature, icon, privacy and branding audit (log /private/tmp/foliance-build4-store-final.log). Package SHA-256: 1e5a92da00f094522c0553218db84cc5c5a1d4f5932e21dbf19596842d2ef14b. Both the final store bundle and ordinary preview omit the screenshot-capture flag. The one-off preview capture flag only resizes an actual native window to 1280×800 points; it does not generate fake UI or analysis.

App Store Connect now has Foliance, macOS app ID 6828975143, version 1.0.0, English (U.S.), Productivity with Reference secondary category. Name, subtitle, promotional text, description, keywords, URLs, copyright and private App Review account-contact details are saved. Pricing is $0.00 with public discoverability and availability in all 175 countries on release; manual release remains selected. Existing age ratings show 4+ across 172 countries with regional exceptions; this turn did not re-answer the rating questionnaire.

The user confirmed ownership/redistribution permission for the original code/assets, authorized the third-party content-rights declaration, and it was saved. The user confirmed all Developer-account projects are personal/noncommercial; EU account non-trader compliance is Active. Do not reuse that answer after a business model changes.

App Privacy was explicitly approved, configured and published: Email Address, User ID, Device ID and Other User Content; each linked to the user, App Functionality, no tracking. Email is conservatively disclosed because reauthorization sends an email hint and prior identity token; OpenAI does not clearly specify hint retention. The user approved the exact conservative declaration and Apple’s final accuracy/update certification. Config manifest, bundled policy and public policy source are synchronized. No private contact details belong in public files.

Three actual native screenshots, each 2560×1600, were uploaded and verified in Apple’s listing: overview, findings, and selection with a fictional review note. They use AppStore/Sample.pdf and a separate demonstration workspace; original saved work was not overwritten. The CUA capture bytes were JPEG despite the initial filename; originals are preserved locally under Verification/AppStore-original-captures, and sips changed encoding only to valid PNG, with no resizing/retouching. Strict screenshot integrity/dimension/signing preflight passes. Listing PNGs and Verification material are excluded from public source, while capture instructions remain included.

Remaining: Transporter validation/upload and build association, optional live sign-in/model verification with a user-owned eligible ChatGPT account, Apple review submission, then manual release. No App Store build has been uploaded or submitted as of this record. A distribution signature and successful local audits do not promise Apple acceptance. Preserve historical build 3 package and source archives.


## Local publication receipt (after frozen build 4 export)

Build 4 source and the public privacy-page source were published in commit a0c031668fb2b8b3a808cda78aa7d10343a17366. All 239 App/ files matched the frozen source ZIP’s Git blob hashes and modes. Source ZIP SHA-256: eba38f7a48abef07364555fa4ea10ff5b33ff60d81b71bd4606786ccb85df6f1. This local bookkeeping paragraph was added after that frozen export. Verification/release-build4.json records package/source/screenshot hashes and the test counts.

The normal universal preview rebuild passed its release audit and reopened the fictional demonstration workspace without starting analysis. Reviewer Sample.pdf finished processing and is attached to Apple’s draft; the final review instructions reference it. The GitHub Pages deployment for this commit is workflow run 41102521013, still queued when first checked. Transporter’s App Store installation sheet stalled with no authentication controls; one cleared/retried attempt reached the same sheet. The user was asked to finish installing/signing into Apple’s Transporter. No build upload or review submission was performed.


## Clean build 4 packaging retry

Apple received the initial build 4 installer, then rejected processing with ITMS-91109 because the embedded profile had inherited com.apple.quarantine. That installer is preserved locally as dist/Foliance-1.0.0-build4-rejected-quarantine.pkg; do not upload it again. The initial public source export is preserved as dist/Foliance-1.0.0-build4-before-packaging-fix-source.zip.

The builder now recreates only its generated dist/preview or dist/store app bundle and copies files without extended attributes. Because macOS can still propagate a valid quarantine marker through cp -X, it removes that marker only from the validated profile’s generated bundle copy before signing. It preserves the downloaded original, its metadata and all system protections. The release audit fails if any bundle entry has a quarantine attribute. Shell/Python syntax and an offline xattr fixture passed. The clean signed universal package passed the audit; expansion confirmed no quarantined entries and that the embedded profile bytes equal the original. Clean package SHA-256: f925d6307402aa9fcbb48af02ad139945607e8b50cef3a0f4602d328292b0ff5 (log /private/tmp/foliance-build4-store-clean.log).

Swift sources and tests remain byte-identical to the fully tested build 4 inputs, so no full test rerun was needed for this packaging-only correction. Apple permits reuse of a build number after failed processing; the corrected upload is still version 1.0.0, build 4. Transporter was installed and signed in by the user, and the corrected delivery has been started. The updated live privacy page was verified in the browser. No review submission or release has been performed.
