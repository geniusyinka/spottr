import SwiftUI

@main
struct SpottrApp: App {
    @StateObject private var session = SessionState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var session: SessionState

    var body: some View {
        NavigationStack(path: $session.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .exerciseSelect: ExerciseSelectView()
                    case .workout:        WorkoutView()
                    case .summary:        SummaryView()
                    }
                }
        }
        .tint(Theme.accent)
    }
}

enum Route: Hashable {
    case exerciseSelect
    case workout
    case summary
}
