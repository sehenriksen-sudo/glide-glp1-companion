// SpotlightManager.swift
//
// Indexes app data into CoreSpotlight so users can search medication logs,
// weight entries, and workouts directly from the iOS home screen.
//
// Also handles NSUserActivity continuation so Spotlight result taps
// deep-link into the correct screen via DeepLinkRouter.
//
// Call indexAll(medications:weights:exercises:foods:) after any data change.
// Wire onContinueUserActivity in GlideApp to route the tap.

import CoreSpotlight
import SwiftUI
import Observation

// MARK: - Spotlight item type identifiers

private enum SpotlightType {
    static let medication = "com.glide.medicationlog"
    static let weight     = "com.glide.weightlog"
    static let exercise   = "com.glide.exerciselog"
    static let food       = "com.glide.foodlog"
}

// MARK: - SpotlightManager

@Observable
@MainActor
final class SpotlightManager {

    private(set) var isIndexing = false
    private let index = CSSearchableIndex.default()

    // MARK: Full reindex

    func indexAll(
        medications: [MedicationLog],
        weights:     [WeightLog],
        exercises:   [ExerciseLog],
        foods:       [FoodLog]
    ) async {
        isIndexing = true
        defer { isIndexing = false }

        var items: [CSSearchableItem] = []
        items += medications.map { searchableItem(for: $0) }
        items += weights.map     { searchableItem(for: $0) }
        items += exercises.map   { searchableItem(for: $0) }
        items += foods.map       { searchableItem(for: $0) }

        do {
            try await index.indexSearchableItems(items)
        } catch {
            print("[Spotlight] Indexing failed: \(error)")
        }
    }

    // MARK: Incremental updates

    func index(medication: MedicationLog) async {
        try? await index.indexSearchableItems([searchableItem(for: medication)])
    }

    func index(weight: WeightLog) async {
        try? await index.indexSearchableItems([searchableItem(for: weight)])
    }

    func index(exercise: ExerciseLog) async {
        try? await index.indexSearchableItems([searchableItem(for: exercise)])
    }

    func index(food: FoodLog) async {
        try? await index.indexSearchableItems([searchableItem(for: food)])
    }

    // MARK: Deletion

    func delete(id: UUID, type: String) async {
        let identifier = spotlightID(type: type, id: id)
        try? await index.deleteSearchableItems(withIdentifiers: [identifier])
    }

    func deleteAll() async {
        try? await index.deleteAllSearchableItems()
    }

    // MARK: NSUserActivity → DeepLink

    /// Call from GlideApp's .onContinueUserActivity modifier.
    /// Returns the deep link URL string to pass to DeepLinkRouter.handle(url:)
    static func deepLinkURL(from activity: NSUserActivity) -> URL? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return nil }

        if id.hasPrefix(SpotlightType.medication) {
            return URL(string: "glide://medication")
        } else if id.hasPrefix(SpotlightType.weight) {
            return URL(string: "glide://settings")
        } else if id.hasPrefix(SpotlightType.exercise) {
            return URL(string: "glide://exercise")
        } else if id.hasPrefix(SpotlightType.food) {
            return URL(string: "glide://nutrition")
        }
        return URL(string: "glide://home")
    }

    // MARK: Private builders

    private func searchableItem(for log: MedicationLog) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)

        let conc   = log.asMedication().remainingConcentration()
        let days   = Int(Date.now.timeIntervalSince(log.date) / 86_400)

        attrs.title            = "\(log.medicationType) — \(log.doseMg.formatted()) mg"
        attrs.contentDescription = "Day \(days) · \(conc.percentageString) remaining · \(log.date.formatted(date: .abbreviated, time: .shortened))"
        attrs.keywords         = [log.medicationType, "injection", "shot", "GLP-1",
                                   "semaglutide", "tirzepatide", "ozempic", "wegovy",
                                   "mounjaro", "zepbound", "dose", "medication"]
        attrs.thumbnailData    = sfSymbolPNG("syringe.fill", color: .systemIndigo)
        attrs.domainIdentifier = SpotlightType.medication
        attrs.startDate        = log.date

        return CSSearchableItem(
            uniqueIdentifier: spotlightID(type: SpotlightType.medication, id: log.id),
            domainIdentifier: SpotlightType.medication,
            attributeSet:     attrs
        )
    }

    private func searchableItem(for log: WeightLog) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)

        attrs.title            = String(format: "%.1f kg", log.weight)
        attrs.contentDescription = "Weight logged on \(log.date.formatted(date: .abbreviated, time: .omitted))"
        attrs.keywords         = ["weight", "progress", "kg", "pounds", "tracking", "goal"]
        attrs.thumbnailData    = sfSymbolPNG("scalemass.fill", color: .systemGreen)
        attrs.domainIdentifier = SpotlightType.weight
        attrs.startDate        = log.date

        return CSSearchableItem(
            uniqueIdentifier: spotlightID(type: SpotlightType.weight, id: log.id),
            domainIdentifier: SpotlightType.weight,
            attributeSet:     attrs
        )
    }

    private func searchableItem(for log: ExerciseLog) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)

        var desc = "\(log.durationMinutes) min"
        if log.activeCalories > 0 { desc += " · \(log.activeCalories) kcal" }
        if let dist = log.formattedDistance { desc += " · \(dist)" }
        desc += " · \(log.date.formatted(date: .abbreviated, time: .omitted))"

        attrs.title            = log.workoutType
        attrs.contentDescription = desc
        attrs.keywords         = [log.workoutType, "workout", "exercise", "fitness",
                                   "health", "activity", log.isFromHealthKit ? "Apple Health" : "manual"]
        attrs.thumbnailData    = sfSymbolPNG(log.type.systemImage, color: .systemBlue)
        attrs.domainIdentifier = SpotlightType.exercise
        attrs.startDate        = log.date
        attrs.duration         = NSNumber(value: log.durationMinutes * 60)

        return CSSearchableItem(
            uniqueIdentifier: spotlightID(type: SpotlightType.exercise, id: log.id),
            domainIdentifier: SpotlightType.exercise,
            attributeSet:     attrs
        )
    }

    private func searchableItem(for log: FoodLog) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)

        attrs.title            = log.mealName
        attrs.contentDescription = "\(log.calories) kcal · P \(log.protein)g · C \(log.carbs)g · F \(log.fat)g · \(log.timestamp.formatted(date: .abbreviated, time: .omitted))"
        attrs.keywords         = [log.mealName, "food", "meal", "nutrition", "calories",
                                   "protein", "macros", "diet", "tracking"]
        attrs.thumbnailData    = sfSymbolPNG("fork.knife", color: .systemOrange)
        attrs.domainIdentifier = SpotlightType.food
        attrs.startDate        = log.timestamp
        attrs.calendarItemIdentifier = log.id.uuidString

        return CSSearchableItem(
            uniqueIdentifier: spotlightID(type: SpotlightType.food, id: log.id),
            domainIdentifier: SpotlightType.food,
            attributeSet:     attrs
        )
    }

    private func spotlightID(type: String, id: UUID) -> String {
        "\(type).\(id.uuidString)"
    }

    /// Renders an SF Symbol as PNG data for Spotlight thumbnails.
    private func sfSymbolPNG(_ name: String, color: UIColor) -> Data? {
        let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
            .applying(UIImage.SymbolConfiguration(paletteColors: [color]))
        guard let img = UIImage(systemName: name, withConfiguration: config) else { return nil }
        let size    = CGSize(width: 60, height: 60)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { ctx in
            UIColor.secondarySystemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let rect = CGRect(x: 12, y: 12, width: 36, height: 36)
            img.draw(in: rect)
        }
    }
}
