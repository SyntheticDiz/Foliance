# Foliance review notes

Foliance is an English-language native macOS productivity app for reading and preparing PDF documents. Foliance is free and open source under MIT. No Foliance login, backend, subscription sale or in-app purchase is required.

Apple Intelligence is the default provider. On-device analysis requires a compatible Apple silicon Mac with macOS 26 or later, enabled Apple Intelligence and its model downloaded. PDF reading, local search, saved results and non-AI functions remain available without a model. There is no automatic cloud fallback.

Optional OpenAI API analysis is configured in Settings. Each user supplies their own API key, stored in this app’s non-synchronizing Keychain entry, and explicitly consents to share task content. The user needs their own compatible OpenAI model access and API billing; ChatGPT subscription billing is separate. Missing consent or a key blocks OpenAI requests. Consent can be revoked and the key removed. Requests use HTTPS directly to OpenAI with Responses storage disabled; abuse-monitoring retention can still apply. No publisher-funded AI service or embedded credentials are provided.

For review, open the fictional sample PDF at AppStore/Sample.pdf from the source materials or any PDF with selectable text. Choose Add PDF and inspect the side-by-side reader. Overview is the default reading profile. Report, Project plan and Meeting notes add source-linked relevance reviews. Try a reading goal, inspect a passage and its source page, save a work document and export a PDF brief. Reopening saved work does not trigger AI requests. Original quotations and user notes remain unchanged in English exports.

The optional Continue with ChatGPT path uses OpenAI’s documented open-source flow: loopback OAuth with PKCE, state and nonce checks, signed ID-token verification and explicit plan-usage scope validation. Eligible usage is funded by the selected ChatGPT plan or available credits; Foliance does not sell access or direct users to an upgrade purchase. Account models are retrieved from OpenAI, and no provider or billing fallback is automatic. The app does not obtain ChatGPT conversations. The temporary callback listener binds only to 127.0.0.1.

The sandbox permits user-selected read/write files, security-scoped bookmarks for recent work, and outbound networking for optional OpenAI connections and a loopback-only OAuth callback listener. It does not browse another application’s storage or import settings/credentials. There are no advertising or analytics SDKs.

Ordinary image-only scans require a searchable text layer before import; table extraction may need review. AI interpretations can be incomplete or incorrect. Original source passages remain accessible, with uncertain or unprocessed content marked in the interface.

OpenAI integration reference: https://developers.openai.com/siwc/token-sharing-open-source (free/open-source ChatGPT plan usage). The app source is published at https://github.com/SyntheticDiz/Foliance. No user’s credentials are provided as a review/demo account. On-device analysis and non-AI reading remain independently available; reviewer access to optional account features must be arranged before submission.
