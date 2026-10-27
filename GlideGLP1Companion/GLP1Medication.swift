import Foundation
import Observation

// MARK: - Medication Type

enum GLP1MedicationType: String, CaseIterable, Codable, Identifiable {
    case semaglutide = "Semaglutide"
    case tirzepatide = "Tirzepatide"

    var id: String { rawValue }

    var brandNames: [String] {
        switch self {
        case .semaglutide: ["Ozempic", "Wegovy"]
        case .tirzepatide: ["Mounjaro", "Zepbound"]
        }
    }

    /// Clinically established half-lives used as type-aware defaults.
    /// Semaglutide: ~7 days. Tirzepatide: ~5 days.
    var typicalHalfLifeDays: Double {
        switch self {
        case .semaglutide: 7.0
        case .tirzepatide: 5.0
        }
    }

    /// Available dose strengths in mg for each medication.
    var availableDoses: [Double] {
        switch self {
        case .semaglutide: [0.25, 0.5, 1.0, 1.7, 2.4]
        case .tirzepatide: [2.5, 5.0, 7.5, 10.0, 12.5, 15.0]
        }
    }
}

// MARK: - Concentration Result

struct ConcentrationResult {
    /// Fraction of original dose remaining (0.0–1.0).
    let fraction: Double
    /// Remaining drug in milligrams.
    let remainingMg: Double
    /// Days elapsed since injection.
    let daysElapsed: Double

    /// Percentage string for display, e.g. "43.2%".
    var percentageString: String {
        String(format: "%.1f%%", fraction * 100)
    }

    /// True when less than 5% of the dose remains (clinically negligible).
    var isEffectivelyCleared: Bool { fraction < 0.05 }
}

// MARK: - GLP1Medication

@Observable
final class GLP1Medication: Identifiable, Codable {

    let id: UUID
    var medicationType: GLP1MedicationType
    var shotDate: Date
    /// Injected dose in milligrams.
    var doseMg: Double
    /// Drug-specific half-life in days. Defaults to 5; override per medication type via init.
    var halfLifeDays: Double

    // MARK: Init

    init(
        id: UUID = UUID(),
        medicationType: GLP1MedicationType,
        shotDate: Date = .now,
        doseMg: Double,
        halfLifeDays: Double = 5.0
    ) {
        self.id = id
        self.medicationType = medicationType
        self.shotDate = shotDate
        self.doseMg = doseMg
        self.halfLifeDays = halfLifeDays
    }

    // MARK: Computed Properties

    /// Days elapsed since the injection, relative to now.
    var daysSinceShot: Double {
        max(0, Date.now.timeIntervalSince(shotDate) / 86_400)
    }

    /// Brand names as a formatted string, e.g. "Ozempic / Wegovy".
    var brandNamesDisplay: String {
        medicationType.brandNames.joined(separator: " / ")
    }

    // MARK: Concentration Calculation

    /// Calculates remaining blood concentration at a given point in time.
    ///
    /// Uses first-order elimination kinetics:
    ///   C(t) = C₀ × (0.5)^(t / t½)
    ///
    /// - Parameter date: The date at which to evaluate concentration. Defaults to now.
    /// - Returns: A `ConcentrationResult` with fraction, mg remaining, and days elapsed.
    func remainingConcentration(at date: Date = .now) -> ConcentrationResult {
        let daysElapsed = max(0, date.timeIntervalSince(shotDate) / 86_400)
        let fraction = pow(0.5, daysElapsed / halfLifeDays)
        return ConcentrationResult(
            fraction: fraction,
            remainingMg: doseMg * fraction,
            daysElapsed: daysElapsed
        )
    }

    /// Estimates the date when concentration falls below a given threshold.
    ///
    /// Solving C(t) = threshold for t:
    ///   t = halfLife × log₂(1 / threshold)
    ///
    /// - Parameter threshold: Fractional cutoff (default 0.05 = 5%).
    /// - Returns: The date at which concentration drops below the threshold.
    func estimatedClearanceDate(threshold: Double = 0.05) -> Date {
        precondition((0.0...1.0).contains(threshold), "Threshold must be between 0 and 1")
        let daysToThreshold = halfLifeDays * log2(1.0 / threshold)
        return shotDate.addingTimeInterval(daysToThreshold * 86_400)
    }

    /// A timeline of concentration values sampled at regular intervals.
    ///
    /// Useful for charting with Swift Charts.
    ///
    /// - Parameters:
    ///   - intervalDays: Sampling interval in days (default 0.5).
    ///   - until: End date (default: clearance at 5% threshold).
    /// - Returns: Array of `(date, ConcentrationResult)` tuples.
    func concentrationTimeline(
        intervalDays: Double = 0.5,
        until endDate: Date? = nil
    ) -> [(date: Date, result: ConcentrationResult)] {
        let stop = endDate ?? estimatedClearanceDate(threshold: 0.05)
        let intervalSeconds = intervalDays * 86_400
        var timeline: [(Date, ConcentrationResult)] = []
        var current = shotDate

        while current <= stop {
            timeline.append((current, remainingConcentration(at: current)))
            current = current.addingTimeInterval(intervalSeconds)
        }
        return timeline
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, medicationType, shotDate, doseMg, halfLifeDays
    }
}
