# Foliance Mac App Store distribution

The project has a sandboxed build configuration and a verified public support/privacy website. A local preview is not a distribution-signed App Store upload.

## Publisher setup

1. In Xcode → Settings → Accounts, sign in to your Apple Developer account and select the intended team. Use Manage Certificates to create/download the appropriate Apple Distribution or Mac App Distribution certificate and Mac Installer Distribution certificate. Complete account authentication yourself; do not paste private keys, passwords or certificates into chat or source files.
2. In Certificates, Identifiers & Profiles, register the explicit macOS app ID `app.foliance.mac`. Create its Mac App Store distribution provisioning profile with the application distribution certificate. Download it to a local location outside the shared/public source.
3. In App Store Connect, create the macOS app record for this bundle ID and choose availability, free pricing, seller details, rights and age-rating answers. The app has no in-app purchases or subscription sales. ChatGPT-plan usage follows OpenAI’s free/open-source integration; keep the audited application source publicly available under MIT.
4. Use the live URLs already recorded in ignored `AppStore/Submission.local.json`: support `https://syntheticdiz.github.io/Foliance/support.html` and privacy `https://syntheticdiz.github.io/Foliance/privacy.html`. The team identifier is also stored only in that local file.

## Local signing environment

List available identities with `security find-identity -v`. Installer identities are excluded by a `-p codesigning` filter, so do not use that filter when finding the installer certificate.

Set these environment variables to the identities/profile you installed. The values below describe what to substitute; they are not credentials or working example identities.

```sh
export FOLIANCE_APP_SIGN_IDENTITY='Your Mac application distribution identity'
export FOLIANCE_INSTALLER_SIGN_IDENTITY='Your Mac installer distribution identity'
export FOLIANCE_PROVISION_PROFILE='/absolute/path/to/your/distribution.provisionprofile'
# FOLIANCE_TEAM_ID is read from ignored local submission settings if not set.
python3 scripts/preflight-store.py
bash build-app.sh store
```

`store` builds arm64 and x86_64, validates the profile's team, bundle ID, distribution type and expiry, embeds the profile, signs with sandbox entitlements and creates `dist/Foliance-1.0.0.pkg` with `productbuild`. It does not upload automatically. The builder refuses to present an ad-hoc build as a store package.

Capture App Store screenshots from the final candidate, review the listing/privacy answers and upload the signed package using Transporter. TestFlight or a development-signed export should be used for distribution-build testing; an App Store distribution signature is not intended to be launched directly like a local preview.

## Verification and remaining prerequisites

Run `scripts/test.sh`, `scripts/audit-release.py dist/preview/Foliance.app` and `scripts/preflight-store.py`. See HANDOFF.md for the actual results and unverified steps. A successful source/build audit does not replace App Store validation or review.

No publishing credentials, private keys, passwords or API tokens are committed or embedded. Never add `.p12`, `.p8`, provisioning profiles or `.env` files to public version control. The source packager must omit `Submission.local.json` and all signing material.

## Apple references

- [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/)
- [App Store Connect](https://appstoreconnect.apple.com/)
