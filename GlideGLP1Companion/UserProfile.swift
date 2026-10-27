// UserProfile.swift
//
// SwiftData model for the user's community presence.
// Stored on-device; fields synced to Firestore when community features are active.

import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var displayName:    String
    var bio:            String
    @Attribute(.externalStorage) var photoData: Data?   // JPEG, stored outside SQLite row
    var medicationType: String      // mirrors UserConfiguration.selectedMedication
    var startDate:      Date?       // when they began their GLP-1 journey
    var isDiscoverable: Bool        // opt-in to community matching
    var firestoreUID:   String      // Firebase anonymous auth UID — set once, never changes
    var createdAt:      Date

    init(
        displayName:    String  = "",
        bio:            String  = "",
        photoData:      Data?   = nil,
        medicationType: String  = "",
        startDate:      Date?   = nil,
        isDiscoverable: Bool    = false,
        firestoreUID:   String  = ""
    ) {
        self.id             = UUID()
        self.displayName    = displayName
        self.bio            = bio
        self.photoData      = photoData
        self.medicationType = medicationType
        self.startDate      = startDate
        self.isDiscoverable = isDiscoverable
        self.firestoreUID   = firestoreUID
        self.createdAt      = .now
    }

    // MARK: Computed

    var weeksSinceStart: Int {
        guard let start = startDate else { return 0 }
        return max(0, Int(Date.now.timeIntervalSince(start) / (7 * 86_400)))
    }

    var journeyLabel: String {
        let w = weeksSinceStart
        if w == 0 { return "Just starting out" }
        if w < 4  { return "Week \(w)" }
        let m = w / 4
        return "\(m) month\(m == 1 ? "" : "s") in"
    }
}
