// ProfileEditView.swift
//
// Sheet for editing the user's community profile:
// display name, bio, profile photo, GLP-1 start date, and community visibility toggle.
//
// Usage:
//   .sheet(isPresented: $showEdit) { ProfileEditView(profile: myProfile) }

import SwiftUI
import SwiftData
import PhotosUI

struct ProfileEditView: View {

    @Environment(\.modelContext)   private var context
    @Environment(\.dismiss)        private var dismiss
    @Environment(ChatManager.self) private var chatManager

    @Bindable var profile: UserProfile

    @State private var selectedItem: PhotosPickerItem?
    @State private var isSaving     = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                infoSection
                visibilitySection
                privacyFooter
            }
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onChange(of: selectedItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    // Compress to JPEG at 0.75 quality to keep storage size reasonable
                    if let img = UIImage(data: data),
                       let jpeg = img.jpegData(compressionQuality: 0.75) {
                        profile.photoData = jpeg
                    }
                }
            }
        }
    }

    // MARK: Photo section

    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                PhotosPicker(selection: $selectedItem,
                             matching: .images,
                             photoLibrary: .shared()) {
                    photoCircle
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 26))
                                .symbolRenderingMode(.multicolor)
                                .background(Color(.systemBackground), in: Circle())
                                .offset(x: 5, y: 5)
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)

                if profile.photoData != nil {
                    Button("Remove Photo", role: .destructive) {
                        profile.photoData = nil
                        selectedItem = nil
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var photoCircle: some View {
        if let data = profile.photoData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        } else {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)
                .shadow(color: Color.blue.opacity(0.35), radius: 10, y: 4)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("Add Photo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
        }
    }

    // MARK: Info section

    private var infoSection: some View {
        Section("About You") {
            HStack {
                Text("Name")
                    .foregroundStyle(.secondary)
                TextField("Display name", text: $profile.displayName)
                    .multilineTextAlignment(.trailing)
            }
            TextField("Short bio (optional)", text: $profile.bio, axis: .vertical)
                .lineLimit(3...5)
        }
    }

    // MARK: Visibility section

    private var visibilitySection: some View {
        Section {
            Toggle("Show me in the community", isOn: $profile.isDiscoverable)
                .tint(.blue)

            if profile.isDiscoverable {
                DatePicker(
                    "Started GLP-1",
                    selection: Binding(
                        get:  { profile.startDate ?? Date.now },
                        set:  { profile.startDate = $0 }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )
            }
        } header: {
            Text("Community")
        } footer: {
            Text(profile.isDiscoverable
                 ? "Others can connect with you via anonymous chat. Only your display name, bio, GLP-1 type, and time on your journey are visible."
                 : "Enable this to be matched with other Glide users for anonymous peer support.")
        }
    }

    // MARK: Privacy note

    private var privacyFooter: some View {
        Section {
            Label(
                "Your real identity is never shared. Chats are ephemeral — messages are not retained after you disconnect.",
                systemImage: "lock.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        try? context.save()
        // If we already have a Firebase UID, push the updated profile
        if chatManager.myUID != nil {
            await chatManager.syncProfile(profile, photoData: profile.photoData)
        }
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    let container = try! ModelContainer(for: UserProfile.self, configurations: .init(isStoredInMemoryOnly: true))
    let p = UserProfile(displayName: "Alex", bio: "2 months on Ozempic — feeling great!", medicationType: "Ozempic", isDiscoverable: true)
    container.mainContext.insert(p)
    return ProfileEditView(profile: p)
        .modelContainer(container)
        .environment(ChatManager())
}
