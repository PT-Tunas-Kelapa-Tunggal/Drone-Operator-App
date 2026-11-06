import AppKit
import SwiftUI

/// A safety button that requires continuous holding for a set duration before triggering the action.
/// Follows Apple macOS design principles: high legibility, clean neutral surfaces, and clear visual state.
struct HoldToConfirmButton: View {
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let holdDuration: TimeInterval
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHolding = false
    @State private var progress: Double = 0.0
    @State private var isTriggered = false
    @State private var holdTask: Task<Void, Never>? = nil

    init(
        _ title: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        holdDuration: TimeInterval = 1.5,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.holdDuration = holdDuration
        self.isDisabled = disabled
        self.action = action
    }

    private var accentColor: Color {
        if role == .destructive {
            return Color.red
        }
        return KropsStyle.accent
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Base background container
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isDisabled
                            ? Color.primary.opacity(0.04)
                            : (isHolding ? accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                    )

                // Smooth progress fill when holding
                if isHolding && !isDisabled {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.25))
                        .frame(width: max(0, min(geo.size.width * progress, geo.size.width)))
                        .animation(.linear(duration: 0.05), value: progress)
                }

                // Content Label
                HStack(spacing: 10) {
                    // Leading Icon
                    ZStack {
                        if isTriggered {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.green)
                        } else if let systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(
                                    isDisabled
                                        ? Color.secondary.opacity(0.6)
                                        : (role == .destructive ? Color.red : Color.primary)
                                )
                        }
                    }
                    .frame(width: 20)

                    // Title & Status
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isTriggered ? "Perintah Terkirim" : title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(
                                isDisabled
                                    ? Color.secondary.opacity(0.65)
                                    : (role == .destructive ? Color.red : Color.primary)
                            )

                        if isHolding && !isTriggered && !isDisabled {
                            Text("Tahan: \(Int(progress * 100))%")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(accentColor)
                        }
                    }

                    Spacer()

                    // Trailing State Indicator
                    if isDisabled {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                    } else if isHolding && !isTriggered {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 14, height: 14)
                    } else if !isTriggered {
                        Text("Tahan")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.04), in: Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isHolding
                            ? accentColor.opacity(0.6)
                            : (isDisabled ? Color.primary.opacity(0.06) : Color.primary.opacity(0.1)),
                        lineWidth: isHolding ? 1.5 : 1
                    )
            )
            .scaleEffect(isHolding ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHolding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isDisabled, !isTriggered else { return }
                        if !isHolding {
                            startHolding()
                        }
                    }
                    .onEnded { _ in
                        cancelHolding()
                    }
            )
        }
        .frame(height: 40)
    }

    private func startHolding() {
        isHolding = true
        progress = 0.0
        let startTime = Date()

        holdTask?.cancel()
        holdTask = Task { @MainActor in
            while !Task.isCancelled && isHolding {
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms tick
                guard isHolding && !Task.isCancelled else { break }

                let elapsed = Date().timeIntervalSince(startTime)
                let p = min(1.0, elapsed / holdDuration)
                self.progress = p

                if p >= 1.0 {
                    triggerAction()
                    break
                }
            }
        }
    }

    private func cancelHolding() {
        guard !isTriggered else {
            isHolding = false
            return
        }
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(.easeOut(duration: 0.18)) {
            progress = 0.0
        }
    }

    private func triggerAction() {
        holdTask?.cancel()
        holdTask = nil
        isTriggered = true
        progress = 1.0
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic, performanceTime: .now
        )
        action()

        // Reset state after showing confirmation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.isTriggered = false
            self.isHolding = false
            withAnimation(.easeOut(duration: 0.2)) {
                self.progress = 0.0
            }
        }
    }
}
