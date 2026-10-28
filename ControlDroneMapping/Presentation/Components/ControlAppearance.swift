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

/// Size variants for primary buttons. Each view has at most one primary action, and
/// buttons that sit side by side share one size.
enum KropsButtonSize {
    /// Inside list and table rows, next to small secondary controls.
    case compact
    /// Inside content sections, forms, sheets and dialogs.
    case regular
    /// The main action of a screen: footers, side panels and map overlays.
    case large

    var controlSize: ControlSize {
        switch self {
        case .compact: return .small
        case .regular: return .regular
        case .large: return .large
        }
    }
}

// One appearance for every primary action: prominent glass, capsule shape and the
// brand tint, sized by variant. Text size follows the system control size.
private struct PrimaryActionAppearance: ViewModifier {
    var size: KropsButtonSize
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                .controlSize(size.controlSize).tint(KropsStyle.accent)
        } else {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .controlSize(size.controlSize).tint(KropsStyle.accent)
        }
    }
}
private struct ToolbarActionAppearance: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            // Neutral glass: drop the brand tint inherited from the app root.
            content.buttonStyle(.glass).controlSize(.regular).font(.body).tint(nil)
        } else {
            content.buttonStyle(.bordered).controlSize(.regular).font(.body).tint(nil)
        }
    }
}
// Controls floating over the map use glass; earlier systems get a material chip.
private struct FloatingControlAppearance<S: Shape>: ViewModifier {
    var shape: S
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(KropsStyle.border))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        }
    }
}
// Text-heavy panels over satellite imagery stay opaque for legibility.
private struct FloatingPanelAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content.background(KropsStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(KropsStyle.border))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
    }
}
extension View {
    func kropsPrimaryAction(size: KropsButtonSize = .regular) -> some View {
        modifier(PrimaryActionAppearance(size: size))
    }
    func kropsToolbarAction() -> some View { modifier(ToolbarActionAppearance()) }
    func kropsFloatingControl<S: Shape>(in shape: S) -> some View {
        modifier(FloatingControlAppearance(shape: shape))
    }
    func kropsFloatingPanel() -> some View { modifier(FloatingPanelAppearance()) }
}
