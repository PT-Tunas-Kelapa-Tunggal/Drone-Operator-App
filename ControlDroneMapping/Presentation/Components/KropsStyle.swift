import AppKit
import SwiftUI

enum KropsStyle {
    static let selection = Color(red: 0.07, green: 0.29, blue: 0.21)
    static let accent = adaptive(
        light: NSColor(red: 0.07, green: 0.29, blue: 0.21, alpha: 1),
        dark: NSColor(red: 0.40, green: 0.78, blue: 0.56, alpha: 1))
    static let canvas = adaptive(
        light: NSColor(red: 0.95, green: 0.96, blue: 0.95, alpha: 1),
        dark: NSColor(red: 0.055, green: 0.067, blue: 0.087, alpha: 1))
    static let surface = adaptive(light: .white, dark: NSColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1))
    static let border = Color.primary.opacity(0.07)
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }
}
