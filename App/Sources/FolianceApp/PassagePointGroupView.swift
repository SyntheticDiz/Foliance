import SwiftUI

struct PassagePointGroupView<Content: View>: View {
    let points: [Insight]
    let showSource: (Int, String) -> Void
    let content: (Insight) -> Content
    @State private var showingPassageReader = false

    private var firstPoint: Insight? { points.first }

    private var parentPages: [Int] {
        guard let firstPoint else { return [] }
        var seen = Set<Int>()
        return (firstPoint.passageSources ?? []).compactMap { source in
            seen.insert(source.page).inserted ? source.page : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(UIStrings.text("Passage · p. " + parentPages.map { String($0) }.joined(separator: ", ")))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Button(UIStrings.text("Lees passage"), systemImage: "text.alignleft") {
                        showingPassageReader = true
                    }
                    .buttonStyle(FocusQuietActionStyle())
                    .help(UIStrings.text("Lees de volledige bovenliggende passage"))
                }
                Text(UIStrings.text("\(points.count) punten in deze weergave"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                if index > 0 { Divider().padding(.horizontal, 12) }
                content(point)
            }
        }
        .readingSurface()
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showingPassageReader) {
            if let firstPoint {
                PassageReaderView(point: firstPoint, showSource: showSource)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
