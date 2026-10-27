// PaywallView.swift
//
// Requires SubscriptionManager injected via @Environment or passed directly.
// Add to your app:
//   .environment(subscriptionManager)  // from @main App body
//
// Usage:
//   .sheet(isPresented: $showPaywall) { PaywallView() }

import SwiftUI
import RevenueCat

// MARK: - Paywall View

struct PaywallView: View {

    @Environment(SubscriptionManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PlanOption = .annual
    @State private var errorMessage: String?

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                    .padding(.bottom, 32)

                if store.isLoading && store.offerings == nil {
                    ProgressView()
                        .padding(40)
                } else {
                    planCards
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    purchaseButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    if let msg = errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                    }

                    restoreButton
                        .padding(.bottom, 16)

                    footerLinks
                        .padding(.bottom, 32)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay(alignment: .topTrailing) { closeButton }
        .task {
            if store.offerings == nil {
                await store.fetchOfferings()
            }
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Gradient background
            LinearGradient(
                stops: [
                    .init(color: Color.blue.opacity(0.85), location: 0),
                    .init(color: Color.indigo.opacity(0.70), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            .frame(height: 320)

            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

                VStack(spacing: 6) {
                    Text("Unlock Premium")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Predictive tracking, concentration curves,\ninsights & anonymous community chat.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }

                featuresGrid
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private var featuresGrid: some View {
        let features: [(icon: String, label: String)] = [
            ("waveform.path.ecg", "Concentration Curves"),
            ("fork.knife.circle.fill", "Food Noise Alerts"),
            ("calendar.badge.clock", "Dose Predictions"),
            ("chart.bar.fill", "Weekly Insights"),
            ("person.2.wave.2.fill", "Community Chat"),
        ]

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(features, id: \.label) { f in
                HStack(spacing: 7) {
                    Image(systemName: f.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(f.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.15), in: Capsule())
            }
        }
    }

    // MARK: Plan Cards

    private var planCards: some View {
        VStack(spacing: 12) {
            if let annual = store.annualPackage {
                PlanCard(
                    package: annual,
                    option: .annual,
                    isSelected: selectedPlan == .annual,
                    savingsPercent: savingsPercent,
                    onTap: { selectedPlan = .annual }
                )
            }
            if let monthly = store.monthlyPackage {
                PlanCard(
                    package: monthly,
                    option: .monthly,
                    isSelected: selectedPlan == .monthly,
                    savingsPercent: nil,
                    onTap: { selectedPlan = .monthly }
                )
            }

            if store.offerings == nil && !store.isLoading {
                Text("Could not load subscription options.\nCheck your connection and try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
            }
        }
    }

    // MARK: Purchase Button

    private var purchaseButton: some View {
        Button {
            Task { await executePurchase() }
        } label: {
            Group {
                if store.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(purchaseButtonLabel)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(purchasePackage == nil
                        ? AnyShapeStyle(Color.secondary)
                        : AnyShapeStyle(LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                          ))
                    )
            }
            .foregroundStyle(.white)
        }
        .disabled(store.isLoading || purchasePackage == nil)
    }

    // MARK: Restore

    private var restoreButton: some View {
        Button {
            Task { await executeRestore() }
        } label: {
            Group {
                if store.isRestoring {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Restore Purchases")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .disabled(store.isRestoring)
    }

    // MARK: Footer

    private var footerLinks: some View {
        HStack(spacing: 4) {
            Link("Terms of Use", destination: URL(string: "https://example.com/terms")!)
            Text("·")
            Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    // MARK: Close Button

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.top, 16)
        .padding(.trailing, 20)
    }

    // MARK: Helpers

    private var purchasePackage: Package? {
        switch selectedPlan {
        case .annual:  return store.annualPackage
        case .monthly: return store.monthlyPackage
        }
    }

    private var purchaseButtonLabel: String {
        guard let pkg = purchasePackage else { return "Select a Plan" }
        switch selectedPlan {
        case .annual:
            let formatted = pkg.storeProduct.localizedPriceString
            return "Subscribe — \(formatted)/year"
        case .monthly:
            let formatted = pkg.storeProduct.localizedPriceString
            return "Subscribe — \(formatted)/month"
        }
    }

    /// Percentage saved buying annual vs monthly (nil when monthly package unavailable).
    private var savingsPercent: Int? {
        guard let monthlyPrice = store.monthlyPackage?.storeProduct.price else { return nil }
        return store.annualPackage?.storeProduct.savingsPercent(comparedToMonthlyPrice: monthlyPrice)
    }

    private func executePurchase() async {
        guard let pkg = purchasePackage else { return }
        errorMessage = nil
        do {
            let activated = try await store.purchase(pkg)
            if activated { dismiss() }
        } catch let err as SubscriptionError where err.isCancellation {
            // User cancelled — silent, no error shown
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func executeRestore() async {
        errorMessage = nil
        do {
            try await store.restorePurchases()
            if store.isPremium { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Plan Option

private enum PlanOption {
    case monthly, annual
}

// MARK: - Plan Card

private struct PlanCard: View {

    let package:       Package
    let option:        PlanOption
    let isSelected:    Bool
    let savingsPercent: Int?
    let onTap:         () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Radio indicator
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.blue : Color.secondary.opacity(0.4),
                                      lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    }
                }

                // Plan label
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(option == .annual ? "Annual" : "Monthly")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)

                        if let pct = savingsPercent {
                            Text("Save \(pct)%")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green, in: Capsule())
                        }
                    }

                    if option == .annual,
                       let ppm = package.storeProduct.formattedPricePerMonth {
                        Text("\(ppm)/mo · billed annually")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("billed monthly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Price
                Text(package.storeProduct.localizedPriceString)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.blue : .primary)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: isSelected ? Color.blue.opacity(0.18) : Color.black.opacity(0.06),
                        radius: isSelected ? 8 : 4,
                        y: 2
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.blue : Color.clear,
                                lineWidth: 2
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if option == .annual {
                Text("BEST VALUE")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue, in: Capsule())
                    .offset(x: -12, y: -10)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
        .environment(SubscriptionManager())
}
