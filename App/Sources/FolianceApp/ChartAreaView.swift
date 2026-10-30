import SwiftUI

struct ChartAreaView: View {
    let page: Int
    let select: (CGRect) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var left = 0.0
    @State private var top = 0.0
    @State private var width = 100.0
    @State private var height = 100.0
    private var valid: Bool {
        [left, top, width, height].allSatisfy(\.isFinite) && left >= 0 && top >= 0 && width > 0 && height > 0 && left + width <= 100 && top + height <= 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIStrings.text("Choose chart area")).font(.title2.bold())
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("PDF page \(page)").font(.callout)
                            Text(UIStrings.text("Enter the area as a percentage of the page. Left and top are distances from the page edge. Include the title and legend."))
                                .fixedSize(horizontal: false, vertical: true)
                            if geometry.size.width >= 520 {
                                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                                    GridRow {
                                        field("From left (%)", value: $left)
                                        field("From top (%)", value: $top)
                                    }
                                    GridRow {
                                        field("Width (%)", value: $width)
                                        field("Height (%)", value: $height)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    field("From left (%)", value: $left)
                                    field("From top (%)", value: $top)
                                    field("Width (%)", value: $width)
                                    field("Height (%)", value: $height)
                                }
                            }
                            if !valid { Text(UIStrings.text("The area must fit entirely within the page.")) .foregroundStyle(.orange) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button(UIStrings.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(UIStrings.text("Use area")) {
                            select(CGRect(x: left / 100, y: 1 - (top + height) / 100, width: width / 100, height: height / 100))
                            dismiss()
                        }.buttonStyle(FocusPrimaryButtonStyle()).disabled(!valid).keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 340, idealWidth: 520, minHeight: 360, idealHeight: 500)
        .buttonStyle(FocusSecondaryButtonStyle())
    }

    private func field(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(UIStrings.text(label))
            TextField(UIStrings.text(label), value: value, format: .number).labelsHidden()
                .textFieldStyle(FocusInputFieldStyle()).frame(width: 100)
                .accessibilityLabel(UIStrings.text(label))
        }
    }
}
