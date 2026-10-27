// PremiumGate.swift
//
// Usage — gate any view behind a premium subscription:
//
//   PredictiveCalculatorView()
//       .requiresPremium()
//
// Or present the paywall inline as a sheet from a non-intrusive context:
//
//   NavigationLink("Insights") {
//       PremiumLockedView(feature: "Weekly Insights")
//   }
//
// SubscriptionManager must be in the environment:
//   ContentView().environment(subscriptionManager)

import SwiftUI

// MARK: - PremiumGate ViewModifier

/// Replaces the view with `PaywallView` when the user is not premium.
/// Once a subscription is active the original content is shown without
/// requiring a dismiss — the modifier reacts to `isPremium` changes live.
private struct PremiumGate: ViewModifier {

    @Environment(SubscriptionManager.self) private var store

    func body(content: Content) -> some View {
        if store.isPremium {
            content
        } else {
            PaywallView()
        }
    }
}

// MARK: - View extension

extension View {

    /// Restricts this view to premium subscribers. Non-premium users see
    /// `PaywallView` in-place; the original view is shown immediately once
    /// a subscription is activated.
    ///
    ///     PredictiveCalculatorView()
    ///         .requiresPremium()
    @ViewBuilder
    func requiresPremium() -> some View {
        modifier(PremiumGate())
    }
}

// MARK: - PremiumLockedView

/// A lightweight placeholder card for features behind the paywall.
/// Use inside a NavigationLink destination or as a list row detail view
/// where you want a non-intrusive teaser rather than a full paywall takeover.
struct PremiumLockedView: View {

    /// Name of the feature being promoted, e.g. "Weekly Insights".
    let feature: String

    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.blue)

            VStack(spacing: 8) {
                Text(feature)
                    .font(.title2.weight(.bold))

                Text("This feature is available with\na Premium subscription.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showPaywall = true
            } label: {
                Label("Upgrade to Premium", systemImage: "star.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(colors: [.blue, .indigo],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

// MARK: - Preview

#Preview("Locked — not premium") {
    // SubscriptionManager with no active subscription
    PredictiveCalculatorPlaceholder()
        .requiresPremium()
        .environment(SubscriptionManager())
}

#Preview("Locked card") {
    PremiumLockedView(feature: "Predictive Calculator")
        .environment(SubscriptionManager())
}

// Placeholder so the preview compiles independently of your real view.
private struct PredictiveCalculatorPlaceholder: View {
    var body: some View {
        Text("Predictive Calculator")
            .font(.largeTitle)
    }
}
