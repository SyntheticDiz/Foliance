# App Store listing and release status

## Saved App Store Connect metadata

- **App:** Foliance · macOS · app ID `6828975143`
- **Version:** 1.0.0
- **Build status:** Build 4 was delivered but failed App Store processing with error 91109 and is not a release candidate. Build 5 is required.
- **Name:** Foliance (reserved)
- **Subtitle:** Read and review PDF reports
- **Primary category:** Productivity
- **Price:** $0.00 in all 175 countries/regions
- **Discoverability:** Public (default)
- **Availability:** 175 countries/regions, available on app release
- **Release:** Manual release selected
- **Third-party content rights:** Yes, explicitly authorized and saved
- **EU trader status:** Non-trader, explicitly confirmed; Done, compliance Active
- **App Privacy:** Published with four categories—email, user ID, device ID and other user content. Each is linked to App Functionality and marked not used for tracking.
- **Age rating:** Existing 4+ rating and 172 country/region exceptions verified. No age-rating questionnaire answers were entered or re-audited as part of this status update.
- **Support URL:** https://syntheticdiz.github.io/Foliance/support.html
- **Marketing URL:** https://syntheticdiz.github.io/Foliance/
- **Privacy policy URL:** https://syntheticdiz.github.io/Foliance/privacy.html
- **App Review contacts:** Saved privately in App Store Connect
- **Screenshots:** Three 2560 × 1600 PNGs uploaded and confirmed (3 of 10 slots)

The saved English metadata is in [`Metadata.en-US.json`](Metadata.en-US.json). Promotional text, description and keywords should remain consistent with that file.

## App privacy summary

Foliance has no developer account, backend, advertising, analytics or tracking. PDFs, notes, summaries and work files are stored locally unless a user chooses an online OpenAI provider. After separate document-sharing consent, the selected task can send document text, relevant reference text and criteria, reading goals, and questions directly to OpenAI. Continue with ChatGPT also uses the user's OpenAI account for sign-in and model availability; Foliance stores account tokens in its own non-synchronizing Keychain entry. API-key use and ChatGPT-plan use have separate billing paths. Foliance asks OpenAI not to store Responses for later retrieval, but OpenAI abuse-monitoring retention may still apply.

The App Privacy answers have been published after the required Apple legal certification was explicitly approved. The four configured data categories and their App Functionality purpose are listed above; no tracking is declared. The public policy explains the relevant account and cloud-processing details.

## Remaining release work

- Complete the pending regression tests, native checks, release audit and distribution signing for build 5. Build 5 has not yet been verified or packaged.
- Validate the expanded build 5 package, upload it with Transporter and wait for App Store processing. Do not select build 4 as the release candidate.
- Optionally perform a live ChatGPT sign-in and model-catalog check with a user-owned account; this has not been done.
- Submit the app for Apple review. Manual release is selected; the app has not been submitted or approved.

Foliance is free and MIT-licensed, with no paywall, in-app purchases or subscription sales. Optional OpenAI usage is billed or limited according to the user's chosen account and plan; this listing makes no unlimited-usage claim.

## Apple field references

- [App information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Platform version information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
