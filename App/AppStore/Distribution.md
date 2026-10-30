# Foliance Mac App Store distribution

The project has a sandboxed build configuration and a verified public support/privacy website. A local preview is not a distribution-signed App Store upload.

## Publisher setup

1. In Xcode → Settings → Accounts, sign in to your Apple Developer account and select the intended team. Use Manage Certificates to create/download the appropriate Apple Distribution or Mac App Distribution certificate and Mac Installer Distribution certificate. Complete account authentication yourself; do not paste private keys, passwords or certificates into chat or source files.
2. The explicit macOS app ID `app.foliance.mac` is registered. Create or verify its Mac App Store distribution provisioning profile with the application distribution certificate. Download it to a local location outside the shared/public source.
3. The macOS app record exists: [App Store Connect app 6828975143](https://appstoreconnect.apple.com/apps/6828975143/distribution). Saved metadata and status are recorded in `AppStore/Listing.md`: $0.00 pricing in 175 countries/regions, public discoverability, availability on app release in those countries, manual release, the approved third-party content-rights answer, and confirmed EU non-trader status. App Privacy is published. The existing 4+ age rating and 172 country/region exceptions were checked, but this status update did not enter or re-audit age-rating questionnaire answers. The app has no in-app purchases or subscription sales. Foliance is MIT-licensed; optional ChatGPT-plan usage remains subject to OpenAI account eligibility and limits.
4. Use the live URLs already recorded in ignored `AppStore/Submission.local.json`: support `https://syntheticdiz.github.io/Foliance/support.html` and privacy `https://syntheticdiz.github.io/Foliance/privacy.html`. The team identifier is also stored only in that local file.

## Local signing environment

List available identities with `security find-identity -v`. Installer identities are excluded by a `-p codesigning` filter, so do not use that filter when finding the installer certificate.

The ignored `AppStore/Submission.local.json` can hold the local values `appSigningIdentity`, `installerSigningIdentity`, `provisionProfile` and `teamID`. Environment variables take precedence over those settings when non-empty. This keeps machine-specific signing configuration out of the source while allowing a one-off override.

Alternatively, set these environment variables to the identities/profile you installed. The values below describe what to substitute; they are not credentials or working example identities.

```sh
export FOLIANCE_APP_SIGN_IDENTITY='Your Mac application distribution identity'
export FOLIANCE_INSTALLER_SIGN_IDENTITY='Your Mac installer distribution identity'
export FOLIANCE_PROVISION_PROFILE='/absolute/path/to/your/distribution.provisionprofile'
# Each non-empty environment variable overrides its matching ignored local setting.
python3 scripts/preflight-store.py
bash build-app.sh store
```

Three native 2560 × 1600 PNG screenshots have been uploaded and confirmed in App Store Connect (3 of 10 slots). The default `scripts/preflight-store.py` run validates local screenshot PNG structure and dimensions as well as signing and configuration. `build-app.sh store` uses `--allow-missing-screenshots` so it can prepare a signed package if screenshots are absent; that option does not waive validation of any screenshot that is present. The signing identities are checked against installed valid certificates and their required certificate types.

`store` builds arm64 and x86_64, validates the profile's team, bundle ID, distribution type and expiry, embeds the profile, signs with sandbox entitlements and creates `dist/Foliance-1.0.0.pkg` with `productbuild`. It does not upload automatically. The builder refuses to present an ad-hoc build as a store package.

The initial build 4 upload was rejected with error 91109; its clean retry processed successfully. Do not select build 4 as the release candidate. Build 5 passed its offline tests, native Keychain check, release audit, signing and expanded-package validation; upload and App Store processing are the remaining package steps. After those checks pass, upload build 5 using Transporter and wait for processing before submitting for Apple review. A live ChatGPT sign-in and model-catalog check with a user-owned account remains optional and has not been performed. Manual release is selected; availability remains pending Apple review and the manual release action. TestFlight or a development-signed export should be used for distribution-build testing; an App Store distribution signature is not intended to be launched directly like a local preview.

## Verification and remaining prerequisites

Run `scripts/test.sh`, `scripts/audit-release.py dist/preview/Foliance.app` and `scripts/preflight-store.py`. See HANDOFF.md for the actual results and unverified steps. A successful source/build audit does not replace App Store validation or review. Building a package with `--allow-missing-screenshots` does not mean the listing is ready to submit.

No publishing credentials, private keys, passwords or API tokens are committed or embedded. Never add `.p12`, `.p8`, provisioning profiles or `.env` files to public version control. The source packager must omit `Submission.local.json` and all signing material.

## Apple references

- [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/)
- [App Store Connect](https://appstoreconnect.apple.com/)

## Packaging metadata

The builder recreates its generated app bundle and copies inputs without extended attributes. It removes a propagated quarantine marker only from the validated provisioning profile’s copy inside the generated bundle before signing; the original profile remains untouched. The release audit rejects quarantined bundle entries. For build 5, inspect the expanded installer as well as the signed app, then validate the package with Transporter before submission. Build 4 is historical and is not the release candidate.
