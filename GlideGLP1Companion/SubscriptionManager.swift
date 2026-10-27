// SubscriptionManager.swift
//
// SPM dependency — add to Package.swift or Xcode:
//   url:     https://github.com/RevenueCat/purchases-ios
//   version: from "5.0.0"
//   product: RevenueCat
//
// RevenueCat dashboard setup checklist:
//   1. Create an entitlement with identifier "premium"
//   2. Create an Offering with identifier "default"
//   3. Attach a monthly package  (identifier: $rc_monthly)
//   4. Attach an annual  package  (identifier: $rc_annual)
//   5. Copy your iOS API key below (starts with "appl_...")

import Foundation
import RevenueCat

// MARK: - Constants

enum RevenueCatConfig {
    /// Replace with your iOS public API key from the RevenueCat dashboard.
    static let apiKey              = "appl_REPLACE_WITH_YOUR_KEY"
    /// Must match the entitlement identifier created in your RC dashboard.
    static let premiumEntitlement  = "premium"
    /// Standard RC identifiers — rename if you use custom ones.
    static let monthlyIdentifier   = "$rc_monthly"
    static let annualIdentifier    = "$rc_annual"
}

// MARK: - Purchase Error

enum SubscriptionError: LocalizedError {
    case cancelled
    case productNotFound
    case network(underlying: Error)
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:             return nil   // silent — user chose to cancel
        case .productNotFound:       return "This subscription is unavailable. Please try again later."
        case .network(let e):        return "Network error: \(e.localizedDescription)"
        case .unknown(let e):        return e.localizedDescription
        }
    }

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

// MARK: - Subscription Manager

@Observable
@MainActor
final class SubscriptionManager {

    // MARK: Published state
    private(set) var customerInfo:   CustomerInfo?
    private(set) var offerings:      Offerings?
    private(set) var isLoading:      Bool = false
    private(set) var isRestoring:    Bool = false
    private(set) var configureError: String?

    // MARK: Derived premium status

    /// True when the "premium" entitlement is active.
    var isPremium: Bool {
        customerInfo?.entitlements[RevenueCatConfig.premiumEntitlement]?.isActive == true
    }

    /// The active period type of the premium entitlement, if any.
    var activePeriodType: PeriodType? {
        customerInfo?.entitlements[RevenueCatConfig.premiumEntitlement]?.periodType
    }

    /// Renewal / expiration date of the active subscription.
    var expirationDate: Date? {
        customerInfo?.entitlements[RevenueCatConfig.premiumEntitlement]?.expirationDate
    }

    // MARK: Convenience package accessors

    var monthlyPackage: Package? {
        offerings?.current?.monthly
    }

    var annualPackage: Package? {
        offerings?.current?.annual
    }

    // MARK: Configuration

    /// Call once from your @main App initializer, before any view appears.
    /// Pass `userID` if you have your own authentication system; otherwise
    /// RevenueCat creates an anonymous ID automatically.
    func configure(userID: String? = nil) {
        Purchases.logLevel = .warn   // use .debug for development

        if let id = userID {
            Purchases.configure(withAPIKey: RevenueCatConfig.apiKey, appUserID: id)
        } else {
            Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        }

        startCustomerInfoListener()

        Task { await fetchOfferings() }
    }

    // MARK: Offerings

    func fetchOfferings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            configureError = "Could not load subscription options: \(error.localizedDescription)"
        }
    }

    // MARK: Purchase

    /// Returns `true` if the purchase completed successfully.
    /// Throws `SubscriptionError.cancelled` when the user dismisses StoreKit's sheet.
    @discardableResult
    func purchase(_ package: Package) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)

            if result.userCancelled { throw SubscriptionError.cancelled }

            customerInfo = result.customerInfo
            return customerInfo?.entitlements[RevenueCatConfig.premiumEntitlement]?.isActive == true

        } catch let err as SubscriptionError {
            throw err
        } catch ErrorCode.productAlreadyPurchasedError {
            // Edge case: already owns this product — treat as success.
            return true
        } catch ErrorCode.purchaseCancelledError {
            throw SubscriptionError.cancelled
        } catch ErrorCode.networkError {
            throw SubscriptionError.network(underlying: error)
        } catch {
            throw SubscriptionError.unknown(underlying: error)
        }
    }

    // MARK: Restore

    func restorePurchases() async throws {
        isRestoring = true
        defer { isRestoring = false }

        do {
            customerInfo = try await Purchases.shared.restorePurchases()
        } catch ErrorCode.networkError {
            throw SubscriptionError.network(underlying: error)
        } catch {
            throw SubscriptionError.unknown(underlying: error)
        }
    }

    // MARK: Private — Live updates

    private func startCustomerInfoListener() {
        Task {
            // customerInfoStream is an AsyncSequence that emits whenever
            // RevenueCat detects a subscription state change (renewal, cancellation, etc.)
            for await info in Purchases.shared.customerInfoStream {
                customerInfo = info
            }
        }
    }
}

// MARK: - StoreProduct helpers

extension StoreProduct {

    /// Formatted price per month, derived from annual price when needed.
    /// e.g. "$4.17/mo" for a $49.99/year plan.
    var formattedPricePerMonth: String? {
        guard let ppm = pricePerMonth else { return nil }
        return priceFormatter?.string(from: ppm as NSDecimalNumber)
    }

    /// Percentage saved versus a reference monthly price (0–100).
    func savingsPercent(comparedToMonthlyPrice monthlyPrice: Decimal) -> Int? {
        guard let ppm = pricePerMonth, monthlyPrice > 0 else { return nil }
        let ratio     = NSDecimalNumber(decimal: ppm / monthlyPrice).doubleValue
        let percent   = (1.0 - ratio) * 100.0
        return percent > 0 ? Int(percent.rounded()) : nil
    }
}
