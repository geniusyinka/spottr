import Foundation
import SwiftUI

/// How the realtime coach behaves for a session. `.form` is the full
/// form-analysis flow; `.hype` skips exercise selection and form feedback —
/// the coach only motivates.
enum CoachMode: String {
    case form, hype
}

/// Top-level app state shared across screens. Tiny enough to live in a single
/// `ObservableObject`; the workout's analyzer is owned by `WorkoutView`.
@MainActor
final class SessionState: ObservableObject {
    @Published var path: [Route] = []
    @Published var mode: CoachMode = .form
    @Published var exercise: ExerciseId = .squat
    @Published var targetReps: Int = 10
    @Published var summary: SetSummary? = nil
    @Published var recordSession: Bool = false
    /// Athlete's first name. Persisted to UserDefaults so the coach addresses
    /// them by name across launches.
    @Published var athleteName: String = UserDefaults.standard.string(forKey: "spottr.athleteName") ?? "Yinka" {
        didSet { UserDefaults.standard.set(athleteName, forKey: "spottr.athleteName") }
    }

    func goExerciseSelect() {
        mode = .form
        path = [.exerciseSelect]
    }
    func startHypeSession() {
        mode = .hype
        summary = nil
        path = [.workout]
    }
    func goWorkout()        { path.append(.workout) }
    func goSummary()        {
        // Idempotent: only push if Summary isn't already at the top.
        if path.last != .summary { path.append(.summary) }
    }
    func popToHome()        { path.removeAll() }
    func startNewSet() {
        summary = nil
        // A motivation session restarts directly; the form flow re-picks the lift.
        path = mode == .hype ? [.workout] : [.exerciseSelect]
    }
}

struct SetSummary: Equatable {
    let exercise: ExerciseId
    let reps: Int
    let avgScore: Double
    let durationMs: Int
    let topIssues: [FormIssueId]
    let recommendation: String
    let recordingURL: URL?
    let recordingPhotoSaveState: PhotoSaveState
    var mode: CoachMode = .form

    static func build(exercise: ExerciseId,
                      reps: [RepCompleted],
                      durationMs: Int,
                      recordingURL: URL? = nil,
                      recordingPhotoSaveState: PhotoSaveState = .notRequested,
                      mode: CoachMode = .form) -> SetSummary {
        guard mode != .hype else {
            return SetSummary(exercise: exercise, reps: reps.count, avgScore: 0, durationMs: durationMs,
                              topIssues: [],
                              recommendation: "Pure motivation session — no form analysis on this one. Nice work putting the time in.",
                              recordingURL: recordingURL,
                              recordingPhotoSaveState: recordingPhotoSaveState,
                              mode: .hype)
        }
        guard !reps.isEmpty else {
            return SetSummary(exercise: exercise, reps: 0, avgScore: 0, durationMs: durationMs,
                              topIssues: [],
                              recommendation: "No reps detected — try positioning yourself fully in frame and starting again.",
                              recordingURL: recordingURL,
                              recordingPhotoSaveState: recordingPhotoSaveState)
        }
        let avg = reps.map(\.score).reduce(0, +) / Double(reps.count)

        var counts: [FormIssueId: Int] = [:]
        for r in reps { for i in r.issues { counts[i.id, default: 0] += 1 } }
        let top = counts.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        return SetSummary(
            exercise: exercise,
            reps: reps.count,
            avgScore: avg,
            durationMs: durationMs,
            topIssues: Array(top),
            recommendation: Self.nextSetRecommendation(reps: reps.count, avg: avg, top: Array(top)),
            recordingURL: recordingURL,
            recordingPhotoSaveState: recordingPhotoSaveState
        )
    }

    private static func nextSetRecommendation(reps: Int, avg: Double, top: [FormIssueId]) -> String {
        if avg >= 0.85, top.isEmpty {
            return "Solid set — \(reps) clean reps. Try \(reps + 2) next set with the same tempo."
        }
        if let primary = top.first {
            return "Focus on: \(primary.label). \(primary.coachHint)"
        }
        if avg < 0.6 {
            return "Drop the rep count next set and prioritize controlled, full-range reps."
        }
        return "Keep the same target next set and concentrate on tempo."
    }
}
