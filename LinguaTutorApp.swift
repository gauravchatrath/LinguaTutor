import SwiftUI

@main
struct LinguaTutorApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var progressStore = ProgressStore.shared
    @StateObject private var speechService = SpeechService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
                .environmentObject(progressStore)
                .environmentObject(speechService)
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 680)
        .windowResizability(.contentSize)
        #endif
    }
}

struct RootView: View {
    @AppStorage("anthropicAPIKey") private var apiKey = ""

    var body: some View {
        if apiKey.isEmpty {
            SettingsView(isOnboarding: true)
        } else {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                LessonView()
            }
            .tabItem { Label("Lesson", systemImage: "book.fill") }

            NavigationStack {
                TestView()
            }
            .tabItem { Label("Test", systemImage: "checkmark.circle.fill") }

            NavigationStack {
                SettingsView(isOnboarding: false)
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
