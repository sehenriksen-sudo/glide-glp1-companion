// SwiftDataModels.swift
//
// All persistent @Model types for GlideGLP1Companion.
// Stored entirely on-device via SwiftData — no external sync.
// Note: UserProfile is defined in UserProfile.swift.
//
// Minimum deployment target: iOS 17

import Foundation
import SwiftData

// MARK: - UserConfiguration

/// Singleton-style record for the user's global app settings.
/// Query with `@Query var configs: [UserConfiguration]` and use `configs.first`.
@Model
final class UserConfiguration {
    var selectedMedication:    String   // GLP1MedicationType.rawValue
    var targetWeight:          Double   // kg or lb — matches user's unit preference
    var currentWeight:         Double
    var monthlyMedicationCost: Double   // local currency
    var isPremiumUnlocked:     Bool     // mirrors RevenueCat entitlement; local cache only

    init(
        selectedMedication:    String  = GLP1MedicationType.semaglutide.rawValue,
        targetWeight:          Double  = 0,
        currentWeight:         Double  = 0,
        monthlyMedicationCost: Double  = 0,
        isPremiumUnlocked:     Bool    = false
    ) {
        self.selectedMedication    = selectedMedication
        self.targetWeight          = targetWeight
        self.currentWeight         = currentWeight
        self.monthlyMedicationCost = monthlyMedicationCost
        self.isPremiumUnlocked     = isPremiumUnlocked
    }
}

// MARK: - MedicationLog

/// One entry per injection event.
@Model
final class MedicationLog {
    @Attribute(.unique) var id: UUID
    var date:           Date
    var doseMg:         Double
    var medicationType: String   // GLP1MedicationType.rawValue

    init(
        id:             UUID   = UUID(),
        date:           Date   = .now,
        doseMg:         Double,
        medicationType: String
    ) {
        self.id             = id
        self.date           = date
        self.doseMg         = doseMg
        self.medicationType = medicationType
    }

    /// Convenience — typed enum from the stored raw value.
    var type: GLP1MedicationType? { GLP1MedicationType(rawValue: medicationType) }

    /// Live `GLP1Medication` view-model built from this log entry.
    /// Uses the medication type's typical half-life as the default.
    func asMedication() -> GLP1Medication {
        GLP1Medication(
            medicationType: type ?? .semaglutide,
            shotDate:        date,
            doseMg:          doseMg,
            halfLifeDays:    type?.typicalHalfLifeDays ?? 5.0
        )
    }
}

// MARK: - WeightLog

/// One weight measurement, recorded manually or via HealthKit import.
@Model
final class WeightLog {
    @Attribute(.unique) var id: UUID
    var date:   Date
    var weight: Double   // stored in kg; convert to lb in the UI layer if needed

    init(id: UUID = UUID(), date: Date = .now, weight: Double) {
        self.id     = id
        self.date   = date
        self.weight = weight
    }
}

// MARK: - FoodLog

/// One meal entry, typically populated from the AI camera scan.
@Model
final class FoodLog {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var mealName:  String
    var calories:  Int
    var protein:   Int   // grams
    var carbs:     Int   // grams
    var fat:       Int   // grams

    init(
        id:        UUID   = UUID(),
        timestamp: Date   = .now,
        mealName:  String,
        calories:  Int,
        protein:   Int,
        carbs:     Int,
        fat:       Int
    ) {
        self.id        = id
        self.timestamp = timestamp
        self.mealName  = mealName
        self.calories  = calories
        self.protein   = protein
        self.carbs     = carbs
        self.fat       = fat
    }

    /// Percentage of calories from protein (useful for GLP-1 muscle-preservation goal).
    var proteinCaloriePercent: Double {
        guard calories > 0 else { return 0 }
        return Double(protein * 4) / Double(calories) * 100
    }
}

// MARK: - ExerciseLog

/// One exercise/workout session, sourced from HealthKit or entered manually.
@Model
final class ExerciseLog {
    @Attribute(.unique) var id: UUID
    var date:             Date
    var workoutType:      String        // ExerciseType.rawValue
    var durationMinutes:  Int
    var activeCalories:   Int           // kcal; 0 when not known
    var distanceMeters:   Double        // 0 when not applicable (e.g. strength)
    var notes:            String        // optional free-text
    /// "healthkit" — imported from HKWorkout  |  "manual" — user typed it in
    var source:           String

    init(
        id:               UUID    = UUID(),
        date:             Date    = .now,
        workoutType:      String,
        durationMinutes:  Int,
        activeCalories:   Int     = 0,
        distanceMeters:   Double  = 0,
        notes:            String  = "",
        source:           String  = "manual"
    ) {
        self.id               = id
        self.date             = date
        self.workoutType      = workoutType
        self.durationMinutes  = durationMinutes
        self.activeCalories   = activeCalories
        self.distanceMeters   = distanceMeters
        self.notes            = notes
        self.source           = source
    }

    var type: ExerciseType { ExerciseType(rawValue: workoutType) ?? .other }
    var isFromHealthKit: Bool { source == "healthkit" }

    /// Distance in km, formatted for display.
    var formattedDistance: String? {
        guard distanceMeters > 0 else { return nil }
        let km = distanceMeters / 1000
        return km >= 1
            ? String(format: "%.2f km", km)
            : String(format: "%.0f m",  distanceMeters)
    }
}

// MARK: - ExerciseType

enum ExerciseType: String, CaseIterable, Identifiable {
    // Cardio
    case running        = "Running"
    case walking        = "Walking"
    case cycling        = "Cycling"
    case swimming       = "Swimming"
    case rowing         = "Rowing"
    case elliptical     = "Elliptical"
    case stairClimbing  = "Stair Climbing"
    // Strength & flexibility
    case strengthTraining = "Strength Training"
    case yoga           = "Yoga"
    case pilates        = "Pilates"
    case stretching     = "Stretching"
    // HIIT / sports
    case hiit           = "HIIT"
    case crossFit       = "CrossFit"
    case basketball     = "Basketball"
    case soccer         = "Soccer"
    case tennis         = "Tennis"
    case hiking         = "Hiking"
    case dance          = "Dance"
    case other          = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .running, .walking:         return "figure.run"
        case .cycling:                   return "figure.outdoor.cycle"
        case .swimming:                  return "figure.pool.swim"
        case .rowing:                    return "figure.rowing"
        case .elliptical:                return "figure.elliptical"
        case .stairClimbing:             return "figure.stair.stepper"
        case .strengthTraining:          return "figure.strengthtraining.traditional"
        case .yoga:                      return "figure.yoga"
        case .pilates, .stretching:      return "figure.flexibility"
        case .hiit, .crossFit:           return "figure.highintensity.intervaltraining"
        case .basketball:                return "figure.basketball"
        case .soccer:                    return "figure.soccer"
        case .tennis:                    return "figure.tennis"
        case .hiking:                    return "figure.hiking"
        case .dance:                     return "figure.dance"
        case .other:                     return "figure.mixed.cardio"
        }
    }

    /// True for activities where distance is meaningful.
    var tracksDistance: Bool {
        switch self {
        case .running, .walking, .cycling, .swimming, .rowing, .hiking: return true
        default: return false
        }
    }
}
