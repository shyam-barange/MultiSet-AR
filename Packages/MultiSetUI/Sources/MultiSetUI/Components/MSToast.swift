import SwiftUI

public struct MSToast: Equatable, Identifiable, Sendable {
    public enum Tone: Sendable { case success, failure, info }

    public let id = UUID()
    public let message: String
    public let tone: Tone

    public init(message: String, tone: Tone = .info) {
        self.message = message
        self.tone = tone
    }

    var symbol: String {
        switch tone {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    var color: Color {
        switch tone {
        case .success: MSColor.success
        case .failure: MSColor.danger
        case .info: MSColor.info
        }
    }
}

private struct MSToastOverlay: ViewModifier {
    @Binding var toast: MSToast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                HStack(spacing: MSSpacing.sm) {
                    Image(systemName: toast.symbol).foregroundStyle(toast.color)
                    Text(toast.message)
                        .font(MSFont.callout)
                        .foregroundStyle(MSColor.textPrimary)
                }
                .padding(.horizontal, MSSpacing.lg)
                .padding(.vertical, MSSpacing.md)
                .background(MSColor.surfaceRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(MSColor.borderSubtle, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.top, MSSpacing.sm)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { self.toast = nil }
                }
            }
        }
        .animation(reduceMotion ? .none : .spring(duration: 0.32), value: toast)
    }
}

public extension View {
    func msToast(_ toast: Binding<MSToast?>) -> some View {
        modifier(MSToastOverlay(toast: toast))
    }
}
