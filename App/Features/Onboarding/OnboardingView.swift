import MultiSetUI
import SwiftUI

/// Three cards, skippable, shown once. Nothing here is gated behind an account.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Card {
        let illustration: MSIllustration
        let headline: String
        let body: String
    }

    private let cards = [
        Card(
            illustration: .noMaps,
            headline: "Your space, mapped",
            body: "MultiSet turns a scan of a building into spatial ground truth — a map any camera can recognise."
        ),
        Card(
            illustration: .searching(progress: 0.85),
            headline: "The phone knows where it is",
            body: "Point the camera at the room and VPS works out exactly where you're standing, to within five centimetres."
        ),
        Card(
            illustration: .noObjects,
            headline: "Hand it to a stranger",
            body: "Publish an experience, print the code, and anyone can scan it and follow the line. No install, no account."
        )
    ]

    var body: some View {
        VStack(spacing: MSSpacing.xl) {
            HStack {
                Spacer()
                Button("Skip") { model.completeOnboarding() }
                    .font(MSFont.bodyEmphasis)
                    .foregroundStyle(MSColor.textSecondary)
                    .frame(minHeight: MSSize.minTouchTarget)
                    .accessibilityHint("Goes straight to the app")
            }
            .padding(.horizontal, MSSpacing.lg)

            TabView(selection: $page) {
                ForEach(cards.indices, id: \.self) { index in
                    card(cards[index]).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack(spacing: MSSpacing.sm) {
                Button(page == cards.count - 1 ? "Get started" : "Next") {
                    if page == cards.count - 1 {
                        model.completeOnboarding()
                    } else {
                        withAnimation(reduceMotion ? .none : .easeInOut) { page += 1 }
                    }
                }
                .msButton()
            }
            .padding(.horizontal, MSSpacing.lg)
            .padding(.bottom, MSSpacing.lg)
        }
        .background(MSColor.background.ignoresSafeArea())
    }

    private func card(_ card: Card) -> some View {
        VStack(spacing: MSSpacing.xl) {
            Spacer(minLength: 0)
            MSIllustrationView(card.illustration, size: 180)
            VStack(spacing: MSSpacing.md) {
                Text(card.headline)
                    .font(MSFont.display)
                    .foregroundStyle(MSColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(card.body)
                    .font(MSFont.body)
                    .foregroundStyle(MSColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MSSpacing.xl)
    }
}

#Preview {
    OnboardingView().environmentObject(AppModel.preview())
}
