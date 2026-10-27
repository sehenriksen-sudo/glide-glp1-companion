// ChatManager.swift
//
// Firebase-backed anonymous user matching + ephemeral real-time chat.
//
// ─── Swift Package Manager dependencies ────────────────────────────────────
//  URL:      https://github.com/firebase/firebase-ios-sdk
//  Version:  Up to Next Major from 11.0.0
//  Products: FirebaseAuth, FirebaseFirestore, FirebaseStorage
//
// ─── Firebase console setup ────────────────────────────────────────────────
//  1. console.firebase.google.com → New project
//  2. Add iOS app (bundle ID must match Xcode target) → download
//     GoogleService-Info.plist → drag into Xcode (main target only, NOT widget)
//  3. Authentication → Sign-in method → Anonymous → Enable
//  4. Firestore → Create database → choose region → Start in test mode
//  5. Storage  → Get started → test mode
//  6. Replace test-mode rules with the production rules below before shipping:
//
//  rules_version = '2';
//  service cloud.firestore {
//    match /databases/{database}/documents {
//      match /users/{uid}   { allow read: if request.auth != null;
//                             allow write: if request.auth.uid == uid; }
//      match /waiting/{uid} { allow read: if request.auth != null;
//                             allow write: if request.auth.uid == uid; }
//      match /reports/{id}  { allow create: if request.auth != null; }
//      match /chatRooms/{roomId} {
//        allow read, write: if request.auth.uid in resource.data.participants;
//        match /messages/{msgId} {
//          allow read, write: if request.auth.uid in
//            get(/databases/$(database)/documents/chatRooms/$(roomId)).data.participants;
//        }
//      }
//    }
//  }
//
// ─── Firestore data layout ──────────────────────────────────────────────────
//  /users/{uid}           displayName, bio, medicationType, weeksSinceStart,
//                         isDiscoverable, photoURL?, lastSeen, currentRoomId?
//  /waiting/{uid}         uid, joinedAt
//  /chatRooms/{roomId}    participants:[uid,uid], createdAt, isActive
//  /chatRooms/{roomId}/messages/{id}  senderId, text, sentAt
//  /reports/{id}          reportedUID, reporterUID, reason, roomId?, reportedAt
//
// ─── In GlideApp.swift ──────────────────────────────────────────────────────
//  import Firebase
//  init() { FirebaseApp.configure(); ... }
//  @State private var chatManager = ChatManager()
//  // In body: .environment(chatManager)

import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Value types

/// Profile data fetched from another user's Firestore document.
struct RemoteProfile: Identifiable, Equatable {
    let uid:             String
    let displayName:     String
    let bio:             String
    let medicationType:  String
    let weeksSinceStart: Int
    let photoURL:        URL?

    var id: String { uid }

    var journeyLabel: String {
        let w = weeksSinceStart
        if w == 0 { return "Just starting out" }
        if w < 4  { return "Week \(w)" }
        let m = w / 4
        return "\(m) month\(m == 1 ? "" : "s") in"
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id:       String
    let senderId: String
    let text:     String
    let sentAt:   Date
}

// MARK: - Match state machine

enum MatchState: Equatable {
    case idle
    case authenticating
    case searching
    case matched(RemoteProfile)
    case chatting(RemoteProfile)
    case error(String)
}

// MARK: - ChatManager

@Observable
@MainActor
final class ChatManager {

    private(set) var matchState: MatchState = .idle
    private(set) var messages:   [ChatMessage] = []
    private(set) var myUID:      String?
    private(set) var isSending   = false

    private var waitingListener:  ListenerRegistration?
    private var roomListener:     ListenerRegistration?
    private var messagesListener: ListenerRegistration?

    private var currentRoomId: String?

    private let db      = Firestore.firestore()
    private let storage = Storage.storage()

    // MARK: Authentication

    /// Signs in anonymously with Firebase Auth. Safe to call multiple times.
    func authenticate() async throws {
        if let user = Auth.auth().currentUser {
            myUID = user.uid; return
        }
        matchState = .authenticating
        let result = try await Auth.auth().signInAnonymously()
        myUID = result.user.uid
    }

    // MARK: Profile sync

    /// Pushes the local UserProfile to Firestore so other users can see it during matching.
    func syncProfile(_ profile: UserProfile, photoData: Data?) async {
        guard let uid = myUID else { return }

        var photoURL: String?
        if let data = photoData {
            photoURL = try? await uploadProfilePhoto(data, uid: uid)
        }

        // Persist the Firebase UID back into the local SwiftData record
        if profile.firestoreUID.isEmpty { profile.firestoreUID = uid }

        var doc: [String: Any] = [
            "displayName":    profile.displayName.isEmpty ? "Anonymous" : profile.displayName,
            "bio":            profile.bio,
            "medicationType": profile.medicationType,
            "weeksSinceStart": profile.weeksSinceStart,
            "isDiscoverable": profile.isDiscoverable,
            "lastSeen":       FieldValue.serverTimestamp(),
            "currentRoomId":  NSNull()
        ]
        if let url = photoURL { doc["photoURL"] = url }

        try? await db.collection("users").document(uid).setData(doc, merge: true)
    }

    private func uploadProfilePhoto(_ data: Data, uid: String) async throws -> String {
        let ref = storage.reference().child("profilePhotos/\(uid).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(data, metadata: meta)
        return try await ref.downloadURL().absoluteString
    }

    // MARK: Matching

    /// Enter the waiting room and find a random match.
    func findMatch() async {
        if myUID == nil {
            do { try await authenticate() } catch {
                matchState = .error("Couldn't connect — check your internet connection.")
                return
            }
        }
        guard let uid = myUID else { return }

        matchState    = .searching
        messages      = []
        currentRoomId = nil

        // Register in the waiting room
        try? await db.collection("waiting").document(uid).setData([
            "uid":      uid,
            "joinedAt": FieldValue.serverTimestamp()
        ])

        // Watch the waiting room for other participants
        waitingListener?.remove()
        waitingListener = db.collection("waiting")
            .order(by: "joinedAt")
            .limit(to: 10)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                let others = docs.compactMap { $0.documentID != uid ? $0.documentID : nil }
                guard let partnerUID = others.first else { return }

                // The UID that sorts first lexicographically creates the room.
                // This prevents two simultaneous room-creation attempts.
                if uid < partnerUID {
                    Task { await self.createRoom(myUID: uid, partnerUID: partnerUID) }
                } else {
                    self.waitForRoomAssignment(uid: uid)
                }
            }
    }

    /// The alphabetically-first participant creates the Firestore room document.
    private func createRoom(myUID: String, partnerUID: String) async {
        // Fetch partner profile
        let partnerSnap = try? await db.collection("users").document(partnerUID).getDocument()
        let partner     = remoteProfile(from: partnerSnap?.data() ?? [:], uid: partnerUID)

        // Atomically create room + clean up both from waiting
        let roomRef = db.collection("chatRooms").document()
        let roomId  = roomRef.documentID
        let batch   = db.batch()

        batch.setData([
            "participants": [myUID, partnerUID],
            "createdAt":    FieldValue.serverTimestamp(),
            "isActive":     true
        ], forDocument: roomRef)

        batch.updateData(["currentRoomId": roomId],
                         forDocument: db.collection("users").document(myUID))
        batch.updateData(["currentRoomId": roomId],
                         forDocument: db.collection("users").document(partnerUID))
        batch.deleteDocument(db.collection("waiting").document(myUID))
        batch.deleteDocument(db.collection("waiting").document(partnerUID))

        do {
            try await batch.commit()
        } catch {
            matchState = .error("Matching failed — please try again.")
            return
        }

        waitingListener?.remove()
        enterRoom(roomId: roomId, partner: partner)
    }

    /// The alphabetically-second participant watches their user doc for room assignment.
    private func waitForRoomAssignment(uid: String) {
        roomListener?.remove()
        roomListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self,
                      let roomId = snap?.data()?["currentRoomId"] as? String
                else { return }

                self.roomListener?.remove()
                self.waitingListener?.remove()

                Task {
                    // Fetch the room to learn who the partner is
                    let roomSnap = try? await self.db.collection("chatRooms").document(roomId).getDocument()
                    guard let participants = roomSnap?.data()?["participants"] as? [String],
                          let partnerUID  = participants.first(where: { $0 != uid })
                    else { return }

                    let partnerSnap = try? await self.db.collection("users").document(partnerUID).getDocument()
                    let partner     = self.remoteProfile(from: partnerSnap?.data() ?? [:], uid: partnerUID)
                    self.enterRoom(roomId: roomId, partner: partner)
                }
            }
    }

    private func enterRoom(roomId: String, partner: RemoteProfile) {
        currentRoomId = roomId
        matchState    = .matched(partner)
        listenForMessages(roomId: roomId)
    }

    // MARK: Chat

    /// Transition from matched → chatting state (call after user taps "Start Chat").
    func startChatting() {
        guard case .matched(let p) = matchState else { return }
        matchState = .chatting(p)
    }

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let uid = myUID, let roomId = currentRoomId else { return }
        isSending = true
        defer { isSending = false }
        try? await db.collection("chatRooms").document(roomId)
            .collection("messages")
            .addDocument(data: [
                "senderId": uid,
                "text":     trimmed,
                "sentAt":   FieldValue.serverTimestamp()
            ])
    }

    private func listenForMessages(roomId: String) {
        messagesListener?.remove()
        messagesListener = db.collection("chatRooms").document(roomId)
            .collection("messages")
            .order(by: "sentAt")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                self.messages = docs.compactMap { doc -> ChatMessage? in
                    guard let text     = doc["text"]     as? String,
                          let senderId = doc["senderId"] as? String,
                          let ts       = (doc["sentAt"]  as? Timestamp)
                    else { return nil }
                    return ChatMessage(id: doc.documentID,
                                       senderId: senderId,
                                       text: text,
                                       sentAt: ts.dateValue())
                }
            }
    }

    // MARK: Disconnect

    /// End the current session and return to idle. Safe to call from any state.
    func disconnect() async {
        cleanupListeners()

        if let uid = myUID {
            // Leave waiting room if we were searching
            try? await db.collection("waiting").document(uid).delete()
            // Clear room assignment
            if currentRoomId != nil {
                try? await db.collection("users").document(uid)
                    .updateData(["currentRoomId": NSNull()])
            }
        }
        if let roomId = currentRoomId {
            try? await db.collection("chatRooms").document(roomId)
                .updateData(["isActive": false])
        }

        currentRoomId = nil
        messages      = []
        matchState    = .idle
    }

    /// Report the current match then disconnect.
    func reportCurrentMatch(reason: String = "inappropriate") async {
        guard let uid = myUID else { await disconnect(); return }
        if case .chatting(let partner) = matchState {
            try? await db.collection("reports").addDocument(data: [
                "reportedUID": partner.uid,
                "reporterUID": uid,
                "reason":      reason,
                "roomId":      currentRoomId as Any,
                "reportedAt":  FieldValue.serverTimestamp()
            ])
        }
        await disconnect()
    }

    // MARK: Helpers

    func cleanupListeners() {
        waitingListener?.remove()
        roomListener?.remove()
        messagesListener?.remove()
    }

    private func remoteProfile(from data: [String: Any], uid: String) -> RemoteProfile {
        RemoteProfile(
            uid:             uid,
            displayName:     data["displayName"]     as? String ?? "Anonymous",
            bio:             data["bio"]              as? String ?? "",
            medicationType:  data["medicationType"]  as? String ?? "",
            weeksSinceStart: data["weeksSinceStart"]  as? Int    ?? 0,
            photoURL:        (data["photoURL"] as? String).flatMap { URL(string: $0) }
        )
    }
}
