import XCTest
@testable import FolianceApp

final class OnlineGlossaryTests: XCTestCase {
    let source = GlossaryWebSource(title: "NACo", url: URL(string: "https://en.wikipedia.org/wiki/National_Association_of_Counties")!, text: "The National Association of Counties (NACo) represents county governments.", kind: "Wikipedia introduction")
    func testUnsupportedMeaningNeverBecomesDefinition() {
        let bad = GlossaryWebAnswer(fullName: "National County Organization", explanation: "Invented.", context: "", certain: true, sourceID: 1, quote: source.text)
        let result = OnlineGlossaryService.validate(bad, term: "NACo", sources: [source], model: "fixture")
        XCTAssertFalse(result.certain); XCTAssertEqual(result.fullName, "")
        let inventedCitation = GlossaryWebAnswer(fullName: "National Association of Counties", explanation: "", context: "", certain: true, sourceID: 3, quote: source.text)
        XCTAssertFalse(OnlineGlossaryService.validate(inventedCitation, term: "NACo", sources: [source], model: "fixture").certain)
    }
    func testGroundedMeaningAndModelUncertainty() {
        let good = GlossaryWebAnswer(fullName: "National Association of Counties", explanation: "Represents county governments.", context: "", certain: true, sourceID: 1, quote: source.text)
        let result = OnlineGlossaryService.validate(good, term: "NACo", sources: [source], model: "fixture")
        XCTAssertTrue(result.certain); XCTAssertEqual(result.source?.url, source.url)
        XCTAssertEqual(result.quote, source.text)
        let uncertain = GlossaryWebAnswer(fullName: good.fullName, explanation: good.explanation, context: "", certain: false, sourceID: 1, quote: source.text)
        XCTAssertFalse(OnlineGlossaryService.validate(uncertain, term: "NACo", sources: [source], model: "fixture").certain)
    }
    func testAbbreviationMustBeAWholeTermInEvidence() {
        let answer = GlossaryWebAnswer(fullName: "National Association of Counties", explanation: "Represents county governments.", context: "", certain: true, sourceID: 1, quote: source.text)
        XCTAssertFalse(OnlineGlossaryService.validate(answer, term: "Co", sources: [source], model: "fixture").certain)
        XCTAssertTrue(OnlineGlossaryService.validate(answer, term: "NACo", sources: [source], model: "fixture").certain)
    }
    func testRequestsContainOnlyTermAndNoDocumentContext() throws {
        let request = try GlossaryWebSearch.request(term: "NACo", provider: "wikipedia")
        let items = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(request.url?.host, "en.wikipedia.org")
        XCTAssertEqual(items.first { $0.name == "gsrsearch" }?.value, "\"NACo\"")
        XCTAssertNil(items.first { $0.name == "api_key" })
        XCTAssertThrowsError(try GlossaryWebSearch.request(term: "NACo\" secret document", provider: "wikipedia"))
        XCTAssertThrowsError(try GlossaryWebSearch.request(term: "NACo", provider: "google"))
    }
    func testWikipediaSearchOrderAndSafeLinks() throws {
        let data = Data(#"{"query":{"pages":[{"index":2,"title":"Second","fullurl":"https://en.wikipedia.org/wiki/Second","extract":"Second text"},{"index":1,"title":"First","fullurl":"https://en.wikipedia.org/wiki/First","extract":"First text"},{"index":3,"title":"Invalid","fullurl":"javascript:alert(1)","extract":"no text"},{"index":4,"title":"Legacy language","fullurl":"https://nl.wikipedia.org/wiki/Legacy","extract":"Not accepted for new search results"}]}}"#.utf8)
        let sources = try GlossaryWebSearch.decode(data, provider: "wikipedia")
        XCTAssertEqual(sources.count, 2); XCTAssertEqual(sources.first?.title, "First")
        XCTAssertEqual(sources.first?.text, "First text")
        XCTAssertEqual(sources.first?.kind, "Wikipedia introduction")
    }
    func testCurrentAndLegacyWikipediaSourcesAreRecognizedAndAttributed() {
        let legacy = GlossaryWebSource(title: "Legacy article", url: URL(string: "https://nl.wikipedia.org/wiki/Legacy")!, text: "Legacy source text.", kind: "Wikipedia-introductie")
        let previouslyCached = GlossaryWebSource(title: "Cached English label", url: URL(string: "https://nl.wikipedia.org/wiki/Cached")!, text: "Cached source text.", kind: "Wikipedia introduction")
        XCTAssertTrue(source.isWikipediaIntroduction)
        XCTAssertTrue(legacy.isWikipediaIntroduction)
        XCTAssertTrue(previouslyCached.isWikipediaIntroduction)
        XCTAssertEqual(legacy.displayKind, "Wikipedia introduction")

        let origin = ExportGlossaryItem.wikipediaOrigin(source: source, retrievedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(origin.contains(source.url.absoluteString))
        XCTAssertTrue(origin.contains("CC BY-SA 4.0"))
        XCTAssertTrue(origin.contains(GlossaryWebSource.wikipediaLicenseURL.absoluteString))
        XCTAssertTrue(origin.contains("The Wikipedia source text and its adapted Foliance AI explanation are licensed under CC BY-SA 4.0"))
        XCTAssertTrue(origin.contains("modified paraphrase, not reviewed by Wikipedia"))
        XCTAssertTrue(origin.contains("review the article and its licensing notices."))
        XCTAssertTrue(origin.contains("Your original PDF and notes keep their own terms."))
        XCTAssertFalse(origin.contains(source.text))
    }
    func testAppleExplanationContract() async throws {
        let sourceText = source.text
        let result = try await OnlineGlossaryService.explain(
            term: "NACo", context: "The county follows NACo guidance.", sources: [source], model: "fixture",
            request: { body in
                XCTAssertEqual(body["model"] as? String, AppleAIService.modelID)
                let input = try XCTUnwrap(body["input"] as? String)
                XCTAssertTrue(input.contains("NACo"))
                XCTAssertTrue(input.contains("The county follows NACo guidance."))
                let answer = GlossaryWebAnswer(fullName: "National Association of Counties", explanation: "Represents county governments.", context: "", certain: true, sourceID: 1, quote: sourceText)
                return String(decoding: try JSONEncoder().encode(answer), as: UTF8.self)
            })
        XCTAssertTrue(result.certain)
        let restored = try JSONDecoder().decode(OnlineGlossaryResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(restored.fullName, result.fullName); XCTAssertTrue(restored.fresh)
    }
    func testLiveWikipediaAndAppleWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["Foliance_WEB_LIVE"] == "1" else { throw XCTSkip("Optional local model check") }
        if let reason = AppleAIService.unavailability() { throw XCTSkip(reason) }
        let sources = try await GlossaryWebSearch.search(term: "NACo", provider: "wikipedia")
        XCTAssertFalse(sources.isEmpty)
        let result = try await OnlineGlossaryService.explain(term: "NACo", context: "The county follows NACo guidance about local policy.", sources: sources, model: AppleAIService.modelID)
        XCTAssertTrue(result.certain)
        XCTAssertTrue(result.fullName.localizedCaseInsensitiveContains("counties"))
    }
}
