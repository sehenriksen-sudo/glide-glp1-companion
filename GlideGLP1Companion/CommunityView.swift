// CommunityView.swift
//
// Community tab — anonymous peer matching and ephemeral chat for GLP-1 users.
// Backed by ChatManager (Firebase Auth + Firestore).
//
// Inject via: .environment(chatManager) in GlideApp

import SwiftUI
import SwiftData

// MARK: - Main View

struct CommunityView: View {

    @Environment(\.modelContext)        private var context
    @Environment(ChatManager.self)      private var chatManager
    @Environment(SubscriptionManager.self) private var store

    @Query private var profiles: [UserProfile]

    @State private var showProfileEdit  = false
    @State private var showPaywall      = false
    @State private var showReportAlert  = false
    @State private var searchingPulse   = false
    @State private var messageText      = ""
    @FocusState private var inputFocused: Bool

    private var myProfile: UserProfile? { profiles.first }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                switch chatManager.matchState {
                case .idle:
                    idleView
                case .authenticating:
                    statusView(icon: "network", message: "Connecting…", spinning: true)
                case .searching:
                    searchingView
                case .matched(let partner):
                    matchedView(partner)
                        .transition(.asymmetric(
                            insertion:  .scale(scale: 0.9).combined(with: .opacity),
                            removal:    .opacity)
                        )
                case .chatting(let partner):
                    chattingView(partner)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                case .error(let msg):
                    errorView(message: msg)
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.25), value: chatManager.matchState)
            .navigationTitle("Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfileEdit = true } label: {
                        if let data = myProfile?.photoData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle")
                                .font(.system(size: 20))
                        }
                    }
                }
            }
            .sheet(isPresented: $showProfileEdit) {
                ProfileEditView(profile: ensureProfile())
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .alert("Report User", isPresented: $showReportAlert) {
                Button("Report & Leave", role: .destructive) {
                    Task { await chatManager.reportCurrentMatch(reason: "inappropriate") }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The other user will be reported and you'll be disconnected. Thank you for keeping Glide safe.")
            }
        }
    }

    // MARK: Idle

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 20) {
                myProfileCard
                connectCard
                howItWorksCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
    }

    // ── My profile card ──────────────────────────────────────────────────────

    private var myProfileCard: some View {
        Button { showProfileEdit = true } label: {
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    localProfilePhoto(size: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(myProfile?.displayName.isEmpty == false
                                 ? myProfile!.displayName
                                 : "Set up your profile")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                            if myProfile?.isDiscoverable == true {
                                Label("Visible", systemImage: "eye")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.green, in: Capsule())
                                    .labelStyle(.iconOnly)
                            }
                        }
                        if let med = myProfile?.medicationType, !med.isEmpty {
                            Text(med)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let p = myProfile, p.weeksSinceStart > 0 {
                            Text(p.journeyLabel)
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                if let bio = myProfile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if myProfile?.isDiscoverable != true {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption)
                        Text("Hidden from community. Tap to enable visibility.")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(Color.orange.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .background(Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
    }

    // ── Connect card ─────────────────────────────────────────────────────────

    private var connectCard: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)

                if !store.isPremium {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.multicolor)
                        .offset(x: 14, y: -10)
                }
            }

            Text("Chat Anonymously")
                .font(.title3.weight(.bold))

            Text("Connect with a random person on the same GLP-1 journey. Shared stories, no judgment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button {
                guard store.isPremium else { showPaywall = true; return }
                Task {
                    try? await chatManager.authenticate()
                    if let p = myProfile {
                        await chatManager.syncProfile(p, photoData: p.photoData)
                    }
                    await chatManager.findMatch()
                }
            } label: {
                Label(store.isPremium ? "Find a Match" : "Unlock Community",
                      systemImage: store.isPremium ? "shuffle" : "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    // ── How it works card ────────────────────────────────────────────────────

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            infoRow(icon: "shuffle",       color: .blue,
                    text: "Matched with a random GLP-1 user — anonymously.")
            infoRow(icon: "lock.fill",     color: .green,
                    text: "Only your display name, journey stage, and bio are visible.")
            infoRow(icon: "xmark.circle",  color: .orange,
                    text: "Either person can end the chat at any time.")
            infoRow(icon: "flag.fill",     color: .red,
                    text: "One-tap report keeps the community safe.")
        }
        .padding(16)
        .background(Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Searching

    private var searchingView: some View {
        VStack(spacing: 36) {
            Spacer()

            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.blue.opacity(0.22 - Double(i) * 0.05), lineWidth: 1.5)
                        .frame(width: CGFloat(80 + i * 52),
                               height: CGFloat(80 + i * 52))
                        .scaleEffect(searchingPulse ? 1.0 : 0.82)
                        .animation(
                            .easeInOut(duration: 1.3)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.28),
                            value: searchingPulse
                        )
                }
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 38))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            }
            .frame(height: 210)
            .onAppear { searchingPulse = true }
            .onDisappear { searchingPulse = false }

            VStack(spacing: 8) {
                Text("Finding your match…")
                    .font(.title3.weight(.semibold))
                Text("Looking for someone on the same journey")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await chatManager.disconnect() }
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: Matched (transition screen before chat)

    private func matchedView(_ partner: RemoteProfile) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                // Success ring
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 130, height: 130)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green)
                }

                VStack(spacing: 6) {
                    Text("You're matched!")
                        .font(.title2.weight(.bold))
                    Text("Say hi to \(partner.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Partner card
                partnerProfileCard(partner)

                // Actions
                HStack(spacing: 12) {
                    Button {
                        Task { await chatManager.disconnect() }
                    } label: {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray5),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.primary)
                    }

                    Button { chatManager.startChatting() } label: {
                        Label("Start Chat", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .indigo],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }
            .padding(24)
            Spacer()
        }
    }

    // MARK: Chat

    private func chattingView(_ partner: RemoteProfile) -> some View {
        VStack(spacing: 0) {
            chatHeader(partner)
            Divider()
            ChatMessagesView(
                messages: chatManager.messages,
                myUID:    chatManager.myUID ?? ""
            )
            Divider()
            chatInputBar
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func chatHeader(_ partner: RemoteProfile) -> some View {
        HStack(spacing: 12) {
            AsyncProfilePhoto(url: partner.photoURL, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(partner.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Text([partner.medicationType, partner.journeyLabel]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Report
            Button { showReportAlert = true } label: {
                Image(systemName: "flag")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(9)
                    .background(Color.red.opacity(0.1), in: Circle())
            }

            // Next match
            Button {
                Task { await chatManager.disconnect() }
            } label: {
                Image(systemName: "arrow.shuffle")
                    .font(.system(size: 13))
                    .foregroundStyle(.blue)
                    .padding(9)
                    .background(Color.blue.opacity(0.1), in: Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var chatInputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message…", text: $messageText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray6),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .focused($inputFocused)

            Button {
                let text = messageText
                messageText = ""
                Task { await chatManager.sendMessage(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color(.systemGray3)
                            : .blue
                    )
            }
            .disabled(
                messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || chatManager.isSending
            )
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.bottom, 2)
    }

    // MARK: Status / Error

    private func statusView(icon: String, message: String, spinning: Bool) -> some View {
        VStack(spacing: 16) {
            if spinning {
                ProgressView().scaleEffect(1.3)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 50))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            Text("Connection Error")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await chatManager.findMatch() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func localProfilePhoto(size: CGFloat) -> some View {
        if let data = myProfile?.photoData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        } else {
            Circle()
                .fill(LinearGradient(
                    colors: [.blue, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.white.opacity(0.85))
                }
        }
    }

    private func partnerProfileCard(_ partner: RemoteProfile) -> some View {
        HStack(spacing: 14) {
            AsyncProfilePhoto(url: partner.photoURL, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(partner.displayName)
                    .font(.system(size: 16, weight: .semibold))
                if !partner.medicationType.isEmpty {
                    Text(partner.medicationType)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(partner.journeyLabel)
                    .font(.caption)
                    .foregroundStyle(.blue)
                if !partner.bio.isEmpty {
                    Text(partner.bio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
        .padding(.horizontal, 4)
    }

    /// Returns the existing profile or creates a blank one for editing.
    @discardableResult
    private func ensureProfile() -> UserProfile {
        if let existing = myProfile { return existing }
        let p = UserProfile()
        context.insert(p)
        try? context.save()
        return p
    }
}

// MARK: - Chat Messages List

private struct ChatMessagesView: View {
    let messages: [ChatMessage]
    let myUID:    String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if messages.isEmpty {
                        Text("Say hello 👋")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 40)
                    }
                    ForEach(messages) { msg in
                        MessageBubble(message: msg, isMine: msg.senderId == myUID)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let isMine:  Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMine { Spacer(minLength: 64) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        if isMine {
                            BubbleShape(isMine: true)
                                .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        } else {
                            BubbleShape(isMine: false)
                                .fill(Color(.systemGray5))
                        }
                    }
                    .foregroundStyle(isMine ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message.sentAt, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }

            if !isMine { Spacer(minLength: 64) }
        }
        .padding(.vertical, 2)
    }

}

// MARK: - Chat bubble shape

private struct BubbleShape: Shape {
    let isMine: Bool
    private let cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = cornerRadius
        if isMine {
            // Flat bottom-right corner for sent messages
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // Flat bottom-left corner for received messages
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Async remote profile photo

struct AsyncProfilePhoto: View {
    let url:  URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.6), Color.indigo.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Preview

#Preview {
    let container = try! ModelContainer(
        for: UserProfile.self,
        configurations: .init(isStoredInMemoryOnly: true)
    )
    return CommunityView()
        .modelContainer(container)
        .environment(ChatManager())
}
