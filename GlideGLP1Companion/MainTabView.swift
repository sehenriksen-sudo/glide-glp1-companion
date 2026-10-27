// MainTabView.swift
//
// Root navigation shell — five tabs connecting every screen.
// Set as the root view in GlideApp:
//   ContentView()  →  replace body with  MainTabView()

import SwiftUI
import SwiftData

// MARK: - Tab definition

enum AppTab: Int, CaseIterable {
    case home, medication, nutrition, exercise, community, settings

    var label: String {
        switch self {
        case .home:       return "Home"
        case .medication: return "Medication"
        case .nutrition:  return "Nutrition"
        case .exercise:   return "Exercise"
        case .community:  return "Community"
        case .settings:   return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:       return "house.fill"
        case .medication: return "syringe.fill"
        case .nutrition:  return "fork.knife"
        case .exercise:   return "figure.run"
        case .community:  return "person.2.wave.2.fill"
        case .settings:   return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .home:       return .blue
        case .medication: return .indigo
        case .nutrition:  return .orange
        case .exercise:   return .green
        case .community:  return .teal
        case .settings:   return Color(.systemGray)
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {

    @Environment(DeepLinkRouter.self) private var router

    // Badge counts driven by SwiftData
    @Query(sort: \MedicationLog.date,  order: .reverse) private var medications: [MedicationLog]
    @Query(sort: \FoodLog.timestamp,   order: .reverse) private var foods:        [FoodLog]

    // Local binding shim: drives TabView from router.selectedTab
    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { router.selectedTab = $0 }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // ── Tab content ───────────────────────────────────────────────
            TabView(selection: selectedTabBinding) {
                Tab(.home) {
                    DashboardView()
                }
                Tab(.medication) {
                    // Sheet presented here so it survives tab switches
                    MedicationView()
                        .sheet(isPresented: Binding(
                            get: { router.presentLogShot },
                            set: { router.presentLogShot = $0 }
                        )) {
                            AddMedicationSheet()
                        }
                }
                Tab(.nutrition) {
                    NutritionView()
                        .sheet(isPresented: Binding(
                            get: { router.presentLogMeal },
                            set: { router.presentLogMeal = $0 }
                        )) {
                            AddFoodSheet()
                        }
                }
                Tab(.exercise) {
                    ExerciseLogView()
                        .sheet(isPresented: Binding(
                            get: { router.presentLogExercise },
                            set: { router.presentLogExercise = $0 }
                        )) {
                            AddExerciseSheet()
                        }
                }
                Tab(.community) {
                    CommunityView()
                }
                Tab(.settings) {
                    SettingsView()
                        .sheet(isPresented: Binding(
                            get: { router.presentNotifSettings },
                            set: { router.presentNotifSettings = $0 }
                        )) {
                            NavigationStack { NotificationSettingsView() }
                        }
                }
            }
            .tabViewStyle(.tabBarOnly)
            .tint(router.selectedTab.color)

            // ── Custom floating tab bar ───────────────────────────────────
            CustomTabBar(
                selectedTab:     selectedTabBinding,
                medicationBadge: medicationBadgeCount,
                nutritionBadge:  nutritionBadgeCount
            )
        }
        .ignoresSafeArea(.keyboard)
    }

    // Show a badge on Medication when concentration is in the vulnerable zone
    private var medicationBadgeCount: Int {
        guard let last = medications.first else { return 0 }
        let conc = last.asMedication().remainingConcentration().fraction
        return conc < 0.40 ? 1 : 0
    }

    // Badge on Nutrition when no meals logged today
    private var nutritionBadgeCount: Int {
        foods.filter { Calendar.current.isDateInToday($0.timestamp) }.isEmpty ? 1 : 0
    }
}

// MARK: - Tab convenience init

private extension Tab {
    init(_ tab: AppTab, @ViewBuilder content: () -> Content) where Label == SwiftUI.Label<Text, Image> {
        self.init(tab.label, systemImage: tab.icon, value: tab, content: content)
    }
}

// MARK: - Custom Tab Bar

private struct CustomTabBar: View {

    @Binding var selectedTab: AppTab
    let medicationBadge: Int
    let nutritionBadge:  Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabBarButton(
                    tab:        tab,
                    isSelected: selectedTab == tab,
                    badge:      badge(for: tab)
                ) {
                    withAnimation(.spring(duration: 0.25, bounce: 0.3)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func badge(for tab: AppTab) -> Int {
        switch tab {
        case .medication: return medicationBadge
        case .nutrition:  return nutritionBadge
        default:          return 0
        }
    }
}

// MARK: - Tab Bar Button

private struct TabBarButton: View {

    let tab:        AppTab
    let isSelected: Bool
    let badge:      Int
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    // Pill background for selected state
                    if isSelected {
                        Capsule()
                            .fill(tab.color.opacity(0.15))
                            .frame(width: 50, height: 32)
                    }

                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? tab.color : Color(.systemGray2))
                        .frame(width: 50, height: 32)
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                        .animation(.spring(duration: 0.2), value: isSelected)

                    // Badge dot
                    if badge > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -2)
                    }
                }

                Text(tab.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? tab.color : Color(.systemGray2))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .modelContainer(for: [
            MedicationLog.self, WeightLog.self,
            FoodLog.self, ExerciseLog.self, UserConfiguration.self,
            UserProfile.self,
        ], inMemory: true)
        .environment(SubscriptionManager())
        .environment(HealthKitManager())
        .environment(ChatManager())
}
