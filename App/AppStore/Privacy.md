# Foliance privacy policy

Effective 30 October 2026.

Foliance reads PDFs that you choose and helps you inspect their contents. PDFs, extracted text, saved summaries, questions, notes, selected passages, recent-file bookmarks and work files are stored on your Mac. You choose where exported PDFs and portable work files are saved.

Foliance offers three AI choices. Apple Intelligence is the default and processes document content on your Mac. It requires a compatible Apple silicon Mac, macOS 26 or later, enabled Apple Intelligence and a downloaded English model. Apple may use a network connection to download system models.

OpenAI API is optional. If you select it, supply your own API key and grant document-sharing consent, Foliance sends the document text and passages needed for your task, relevant reference-document text and criteria, your reading goal and questions directly to OpenAI. Your key is used to authenticate those requests. OpenAI API usage is billed to your API account, separately from Foliance and ChatGPT subscriptions. Foliance does not silently fall back to OpenAI.

ChatGPT plan usage is another optional choice for eligible accounts. Continue with ChatGPT opens OpenAI’s authorization page in your system browser; your browser login remains with OpenAI. You authorize identity and plan-usage permissions yourself. Foliance receives a verified account identifier, email, issued client-registration identifier and OAuth tokens, and retrieves the selected account’s model catalog. OpenAI associates the issued registration with the authorized account and workspace. Foliance stores account details and tokens in its separate, non-synchronizing Keychain. Access tokens renew automatically while the connection can be renewed. Signing out attempts to revoke the renewable session and clears local tokens; the saved registration can be used to sign in again.

OpenAI’s sign-in flow also uses a stable, opaque installation host identifier to associate plan usage with this app installation. Foliance stores this identifier in its own preferences and sends it during authorization. On reauthorization, Foliance may send the saved email and prior ID token as account-selection hints. OpenAI documents the account, client-registration and host associations, but does not specify retention periods for the host identifier or sign-in hints. The temporary callback listener binds only to 127.0.0.1 on this Mac. Foliance does not copy credentials from another app or include them in work documents, exports or source code. You can sign out in Foliance and manage app access and usage in ChatGPT settings.

Eligible analysis uses the selected account’s ChatGPT plan or available credits, subject to OpenAI’s eligibility and usage limits. It does not grant Foliance access to your ChatGPT conversations. You separately consent in Foliance before task content is sent to OpenAI. Foliance never silently switches between ChatGPT-plan and API-key billing.

The API key is stored in Foliance’s own, non-synchronizing macOS Keychain entry. It is not embedded in the app, ordinary preferences, work documents, exports, the website or source code. No developer API key is bundled. You can remove your key and revoke OpenAI sharing consent in Settings.

Foliance asks OpenAI not to store Responses for later retrieval. This does not guarantee zero retention. API-key requests follow OpenAI’s API data policies, which may include abuse-monitoring retention: https://developers.openai.com/api/docs/guides/your-data . ChatGPT-plan requests are governed by the applicable ChatGPT account and service terms. Review the terms for your chosen connection before enabling cloud processing for confidential material.

Foliance has no developer account system, advertising, tracking, analytics SDK or cloud synchronization. The developer does not receive your PDFs through a Foliance backend. Apple may separately handle App Store purchases, downloads and system diagnostics under its own policies.

Work files include the original PDF, reference document where applicable, analysis and annotations. Share them only with intended recipients. Deleting a recent-file shortcut does not delete the original file. Reading, local search and saved results remain available without an internet connection.

If you deliberately open an external link, the linked website receives the browser request under its own policy; Foliance does not attach your PDF. The public support website is hosted by GitHub Pages, whose technical request logs are separate from application processing.

Support: https://syntheticdiz.github.io/Foliance/support.html
Public privacy policy: https://syntheticdiz.github.io/Foliance/privacy.html
Do not include private documents, personal information, API keys or sign-in tokens in a public support issue.
