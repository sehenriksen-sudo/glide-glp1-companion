// HealthKitManager.swift
//
// Reads workouts and activity summary data from Apple Health.
// Add to Info.plist before shipping:
//   NSHealthShareUsageDescription  — "Glide reads your workouts to track exercise alongside your GLP-1 schedule."
//
// Add HealthKit capability in Xcode: target → Signing & Capabilities → + HealthKit

import Foundation
import HealthKit
import SwiftData
import Observation

// MARK: - Authorization Status

enum HKAuthorizationState {
    case notDetermined
    case authorized
    case denied
}

// MARK: - Import Result

struct WorkoutImportResult {
    let imported:   Int
    let duplicates: Int
    let failed:     Int
}

// MARK: - HealthKit Manager

@Observable
@MainActor
final class HealthKitManager {

    // ── Public state ──────────────────────────────────────────────────────
    private(set) var authState:      HKAuthorizationState = .notDetermined
    private(set) var isImporting:    Bool                 = false
    private(set) var lastImportResult: WorkoutImportResult?
    private(set) var errorMessage:   String?

    // ── HealthKit store ───────────────────────────────────────────────────
    private let store = HKHealthStore()

    // Types we want to read
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        if let cycling = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
            types.insert(cycling)
        }
        return types
    }

    // MARK: Authorization

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else {
            errorMessage = "Apple Health is not available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authState = .authorized
        } catch {
            authState = .denied
            errorMessage = "Health access denied: \(error.localizedDescription)"
        }
    }

    // MARK: Import workouts → SwiftData

    /// Fetches all workouts from the last `days` days and inserts new ones into the model context.
    /// Skips workouts whose UUID already exists in the store (idempotent).
    @discardableResult
    func importRecentWorkouts(
        days: Int = 90,
        into context: ModelContext
    ) async -> WorkoutImportResult {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        guard isAvailable else {
            let r = WorkoutImportResult(imported: 0, duplicates: 0, failed: 0)
            lastImportResult = r
            return r
        }

        // Fetch existing HealthKit-sourced IDs to avoid duplicates
        let existingIDs: Set<UUID> = {
            let descriptor = FetchDescriptor<ExerciseLog>(
                predicate: #Predicate { $0.source == "healthkit" }
            )
            let existing = (try? context.fetch(descriptor)) ?? []
            return Set(existing.map { $0.id })
        }()

        // Query HealthKit
        let anchor = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: nil)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        do {
            let workouts = try await fetchWorkouts(predicate: predicate, sortDescriptor: sortDescriptor)

            var imported   = 0
            var duplicates = 0
            var failed     = 0

            for workout in workouts {
                guard !existingIDs.contains(workout.uuid) else {
                    duplicates += 1
                    continue
                }
                do {
                    let log = try await exerciseLog(from: workout)
                    context.insert(log)
                    imported += 1
                } catch {
                    failed += 1
                }
            }

            try? context.save()

            let result = WorkoutImportResult(imported: imported, duplicates: duplicates, failed: failed)
            lastImportResult = result
            return result

        } catch {
            errorMessage = "Could not read workouts from Health: \(error.localizedDescription)"
            let r = WorkoutImportResult(imported: 0, duplicates: 0, failed: 0)
            lastImportResult = r
            return r
        }
    }

    // MARK: Weekly exercise minutes (for dashboard summary)

    /// Total exercise minutes in the last 7 days from Health.
    func weeklyExerciseMinutes() async -> Int {
        guard isAvailable,
              let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)
        else { return 0 }

        let start = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let statistics = try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<HKStatistics, Error>) in
            let query = HKStatisticsQuery(
                quantityType: exerciseType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error { cont.resume(throwing: error) }
                else if let stats { cont.resume(returning: stats) }
            }
            store.execute(query)
        }
        let minutes = statistics?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
        return Int(minutes)
    }

    // MARK: Private helpers

    private func fetchWorkouts(
        predicate: NSPredicate,
        sortDescriptor: NSSortDescriptor
    ) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    /// Builds an `ExerciseLog` from an `HKWorkout`, fetching distance statistics from the store.
    private func exerciseLog(from workout: HKWorkout) async throws -> ExerciseLog {
        let duration  = Int(workout.duration / 60)
        let calories  = Int(workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0)
        let distance  = await fetchDistance(for: workout)
        let typeName  = ExerciseType.from(hkWorkoutActivityType: workout.workoutActivityType).rawValue

        return ExerciseLog(
            id:              workout.uuid,
            date:            workout.startDate,
            workoutType:     typeName,
            durationMinutes: duration,
            activeCalories:  calories,
            distanceMeters:  distance,
            notes:           "",
            source:          "healthkit"
        )
    }

    private func fetchDistance(for workout: HKWorkout) async -> Double {
        // Prefer the workout's own total distance when present
        if let d = workout.totalDistance?.doubleValue(for: .meter()) {
            return d
        }
        // Otherwise query cumulative distance within the workout interval
        let distanceTypes: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ]
        for identifier in distanceTypes {
            guard let qtype = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            let pred = HKQuery.predicateForSamples(
                withStart: workout.startDate,
                end: workout.endDate
            )
            if let stats = try? await withCheckedThrowingContinuation({ (cont: CheckedContinuation<HKStatistics, Error>) in
                let q = HKStatisticsQuery(
                    quantityType: qtype,
                    quantitySamplePredicate: pred,
                    options: .cumulativeSum
                ) { _, s, e in
                    if let e { cont.resume(throwing: e) }
                    else if let s { cont.resume(returning: s) }
                }
                store.execute(q)
            }) {
                let meters = stats.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                if meters > 0 { return meters }
            }
        }
        return 0
    }
}

// MARK: - ExerciseType + HKWorkoutActivityType mapping

extension ExerciseType {
    static func from(hkWorkoutActivityType type: HKWorkoutActivityType) -> ExerciseType {
        switch type {
        case .running:                          return .running
        case .walking:                          return .walking
        case .cycling:                          return .cycling
        case .swimming:                         return .swimming
        case .rowing:                           return .rowing
        case .elliptical:                       return .elliptical
        case .stairClimbing:                    return .stairClimbing
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:       return .strengthTraining
        case .yoga:                             return .yoga
        case .pilates:                          return .pilates
        case .flexibility:                      return .stretching
        case .highIntensityIntervalTraining:    return .hiit
        case .crossTraining:                    return .crossFit
        case .basketball:                       return .basketball
        case .soccer:                           return .soccer
        case .tennis:                           return .tennis
        case .hiking:                           return .hiking
        case .dance, .socialDance:              return .dance
        default:                                return .other
        }
    }
}
