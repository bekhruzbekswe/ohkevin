import AppKit
import SwiftUI

/// The few system colours Settings (a standard window) still uses.
enum Tint {
    static let red = Color(nsColor: .systemRed)
    static func control(_ dark: Bool) -> Color { dark ? .white.opacity(0.15) : Color(nsColor: .controlColor) }
}

/// A small plain button of Settings: 24 high, 10 side padding, radius 6.
struct SmallButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(nsColor: .labelColor))
            .padding(.horizontal, 10).frame(height: 24)
            .background(Tint.control(scheme == .dark).opacity(configuration.isPressed ? 0.8 : 1), in: shape)
            .overlay(shape.strokeBorder(contrast == .increased ? Color(nsColor: .separatorColor) : Color.primary.opacity(0.12), lineWidth: contrast == .increased ? 1 : 0.5))
            .shadow(color: .black.opacity(0.08), radius: 0.75, y: 0.5)
            .fixedSize()
            .contentShape(Rectangle())
    }
}
