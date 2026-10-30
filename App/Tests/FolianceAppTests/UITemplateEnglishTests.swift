import Foundation
import XCTest
@testable import FolianceApp

final class UITemplateEnglishTests: XCTestCase {
    func testEveryAppOwnedLocalizedTemplateResolvesWithoutDutchFallback() throws {
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FolianceApp", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var catalog: [(file: String, template: String)] = []
        for file in files where file.lastPathComponent != "UIStrings.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            for marker in ["UIStrings.text(", "AppError(message:"] {
                catalog += localizedTemplates(in: source, marker: marker).map { (file.lastPathComponent, $0) }
            }
        }

        XCTAssertGreaterThan(catalog.count, 100, "The source-template audit should cover the app UI.")
        for item in catalog where containsDutchUIWords(item.template) {
            let resolved = UIStrings.text(item.template)
            XCTAssertNotEqual(resolved, item.template,
                              "Untranslated UI template in \(item.file): \(item.template)")
            XCTAssertFalse(containsDutchUIWords(resolved),
                           "UI translation still contains Dutch in \(item.file): \(resolved)")
        }
    }

    private func localizedTemplates(in source: String, marker: String) -> [String] {
        var results: [String] = []
        var searchStart = source.startIndex

        while let call = source.range(of: marker, range: searchStart..<source.endIndex) {
            var index = call.upperBound
            var parentheses = 1
            while index < source.endIndex && parentheses > 0 {
                if source[index] == "\"" {
                    let parsed = parseString(in: source, from: index)
                    results.append(contentsOf: parsed.values)
                    index = parsed.end
                    continue
                }
                if source[index] == "(" { parentheses += 1 }
                if source[index] == ")" { parentheses -= 1 }
                index = source.index(after: index)
            }
            searchStart = index
        }
        return results
    }

    private func parseString(in source: String, from start: String.Index) -> (values: [String], end: String.Index) {
        var values = [""]
        var index = source.index(after: start)

        while index < source.endIndex {
            let character = source[index]
            if character == "\"" { return (values, source.index(after: index)) }
            if character == "\\" {
                let next = source.index(after: index)
                guard next < source.endIndex else { break }
                if source[next] == "(" {
                    let interpolation = parseInterpolation(in: source, after: next)
                    let alternatives = Array(Set(["7"] + interpolation.strings))
                    values = values.flatMap { prefix in alternatives.map { prefix + $0 } }
                    index = interpolation.end
                    continue
                }
                switch source[next] {
                case "n": values = values.map { $0 + "\n" }
                case "r": values = values.map { $0 + "\r" }
                case "t": values = values.map { $0 + "\t" }
                default: values = values.map { $0 + String(source[next]) }
                }
                index = source.index(after: next)
                continue
            }
            values = values.map { $0 + String(character) }
            index = source.index(after: index)
        }
        return (values, index)
    }

    private func parseInterpolation(in source: String, after openingParenthesis: String.Index) -> (strings: [String], end: String.Index) {
        var strings: [String] = []
        var depth = 1
        var index = source.index(after: openingParenthesis)

        while index < source.endIndex && depth > 0 {
            if source[index] == "\"" {
                let parsed = parseString(in: source, from: index)
                strings.append(contentsOf: parsed.values)
                index = parsed.end
                continue
            }
            if source[index] == "(" { depth += 1 }
            if source[index] == ")" { depth -= 1 }
            index = source.index(after: index)
        }
        return (strings, index)
    }

    private func containsDutchUIWords(_ value: String) -> Bool {
        let pattern = #"(?i)\b(een|het|jouw|deze|dit|zijn|wordt|worden|blijft|blijven|geef|controleer|bekijk|analyse|samenvatting|pagina|bron|selectie|verwerking|gevonden|punten|referentiedocument|overzicht|tabel|afkortingen|uitgebreide|lokaal|lokale|gebruikt|lezen|zoeken|bedragen|voorwaarden|resultaten|kosten|geen|niet|volledige|huidige|bewaarde|opgegeven|schakel|aanvullende|kerngegevens|nog|klaar)\b"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
