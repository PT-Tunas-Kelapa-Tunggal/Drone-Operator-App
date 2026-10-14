import SwiftUI

// Text styles follow the running macOS font metrics. Only the brand mark uses
// a fixed optical size; it is artwork rather than a content-text style.
enum KropsTypography {
    static let pageTitle = Font.title2.weight(.semibold)
    static let sectionTitle = Font.headline
    static let metric = Font.title3.weight(.semibold).monospacedDigit()
    static let supporting = Font.callout
}

struct KropsBrand: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 20, weight: .medium)).symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28).accessibilityHidden(true)
            Text("Krops").font(.system(size: 18, weight: .semibold)).tracking(-0.3)
        }.foregroundStyle(KropsStyle.accent).accessibilityElement(children: .combine)
    }
}

private struct PrimaryActionAppearance: ViewModifier {
    var size: ControlSize
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glassProminent).controlSize(size).font(.body)
        } else {
            content.buttonStyle(.borderedProminent).controlSize(size).font(.body)
        }
    }
}
private struct ToolbarActionAppearance: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glass).controlSize(.regular).font(.body)
        } else {
            content.buttonStyle(.bordered).controlSize(.regular).font(.body)
        }
    }
}
extension View {
    func kropsPrimaryAction(size: ControlSize = .regular) -> some View {
        modifier(PrimaryActionAppearance(size: size))
    }
    func kropsToolbarAction() -> some View { modifier(ToolbarActionAppearance()) }
}
