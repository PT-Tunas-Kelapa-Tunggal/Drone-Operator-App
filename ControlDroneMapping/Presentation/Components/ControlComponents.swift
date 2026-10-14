import SwiftUI

struct ControlPanel<Content: View>: View {
    let title: String
    let state: String?
    private let content: Content
    init(_ title: String, state: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.state = state
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(KropsTypography.sectionTitle)
                Spacer()
                if let state {
                    Label(state, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
            }
            content
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
            KropsStyle.surface, in: RoundedRectangle(cornerRadius: 14)
        ).overlay(RoundedRectangle(cornerRadius: 14).stroke(KropsStyle.border))
    }
}

struct ControlField<Content: View>: View {
    let title: String
    private let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(KropsTypography.supporting).foregroundStyle(.secondary)
            content
        }.frame(maxWidth: .infinity)
    }
}

struct NumberField: View {
    @Binding var value: Double
    let unit: String
    init(_ value: Binding<Double>, unit: String) {
        _value = value
        self.unit = unit
    }
    var body: some View {
        HStack(spacing: 4) {
            TextField("Nilai", value: $value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ControlMetric: View {
    let title: String
    let value: String
    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
