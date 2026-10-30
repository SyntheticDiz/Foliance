# App Review notes

Foliance is a free, open-source macOS PDF reader. It has no Foliance login, developer backend, in-app purchases, subscription sales, advertising or analytics. The interface and new app-authored explanations are in English. Original document quotations and user-entered notes remain unchanged.

## Basic review path

1. Open a PDF with selectable text using **Add PDF**. A fictional selectable-text sample, Sample.pdf, is attached for review and is also available in the project source at `AppStore/Sample.pdf`; it is not required by the app. Any PDF with a searchable text layer can be used.
2. Review the PDF beside the **Overview**. Choose **Report**, **Project plan**, or **Meeting notes** to add a source-linked review. A reading goal and an optional reference document with comparison criteria can guide analysis.
3. Open a finding's source, inspect the full passage, add a note or selected passage, and try local search.
4. Export a PDF brief or save a `.foliance` work document. Reopening saved work does not start AI requests.

## AI providers and consent

Apple Intelligence is the default provider and processes analysis on a compatible Apple silicon Mac running macOS 26 or later, with Apple Intelligence enabled and its model available. PDF reading, local search, saved results and other non-AI functions do not require an AI provider. There is no automatic cloud fallback.

Online analysis is optional. A user may choose OpenAI API access with their own API key and separate API billing, or **Continue with ChatGPT** using an eligible account and its plan/credit limits. These are distinct providers and billing paths. Before task content is sent to OpenAI, the user must grant document-sharing consent in Foliance. Missing consent, credentials or plan access blocks the request; Foliance does not silently switch providers. No review credentials or account are supplied. Reviewers can test the reading workflow without signing in; access to optional account features depends on a reviewer-owned eligible account.

OpenAI requests use HTTPS directly, with Responses storage disabled. This does not guarantee zero retention; OpenAI abuse-monitoring retention may apply. ChatGPT sign-in obtains only the account details and permissions described in the public privacy policy; it does not access ChatGPT conversations. The OAuth callback listener binds only to `127.0.0.1`.

## File and source behavior

The sandbox uses user-selected files and security-scoped bookmarks. Work documents can contain the original PDF, reference material where applicable, analysis, notes, selected passages and reader state. They are stored where the user chooses. Reopening them performs no AI request.

Ordinary image-only scans need a searchable text layer before import. Table extraction can require review; the app does not claim full-page OCR for every scan. AI interpretations can be incomplete or incorrect. A matched quotation establishes its location in the source, not the correctness of an explanation. Important amounts, conditions and conclusions should be checked in the original PDF.

## Public information

- Support: https://syntheticdiz.github.io/Foliance/support.html
- Privacy policy: https://syntheticdiz.github.io/Foliance/privacy.html
- Marketing page: https://syntheticdiz.github.io/Foliance/
- Public source: https://github.com/SyntheticDiz/Foliance/tree/main/App

The App Store privacy questionnaire must be completed separately in App Store Connect based on the final implementation and Apple's current questions. These notes do not assert seller legal status, rights ownership or a publisher contact address.
