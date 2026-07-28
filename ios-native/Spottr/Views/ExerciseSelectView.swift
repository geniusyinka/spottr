import SwiftUI

struct ExerciseSelectView: View {
    @EnvironmentObject var session: SessionState
    @State private var selected: ExerciseId = .squat
    @State private var reps: Int = 10
    private let repOptions = [5, 8, 10, 12, 15]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                label("Exercise")
                VStack(spacing: Spacing.sm) {
                    exerciseRow(.squat, subtitle: "Bodyweight")
                    exerciseRow(.pushup, subtitle: "Bodyweight")
                    exerciseRow(.pullup, subtitle: "Bar")
                }

                label("Target reps")
                    .padding(.top, Spacing.md)
                repsRow

                label("Recording")
                    .padding(.top, Spacing.md)
                recordingToggle

                Spacer(minLength: Spacing.lg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(Theme.bg)
        }
        .navigationTitle("Choose exercise")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selected = session.exercise
            reps = session.targetReps
        }
    }

    // MARK: - Subviews

    private var repsRow: some View {
        // Wrap in a horizontal ScrollView so the pills can never overflow the
        // screen and clip the parent's leading padding.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(repOptions, id: \.self) { n in
                    Button(action: { reps = n }) {
                        Text("\(n)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(reps == n ? Theme.accent : Theme.text)
                            .frame(minWidth: 48)
                            .padding(.vertical, Spacing.sm + 2)
                            .padding(.horizontal, Spacing.md - 2)
                            .background(reps == n ? Theme.accentDim : Theme.card)
                            .cornerRadius(999)
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .strokeBorder(reps == n ? Theme.accent : Theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var startButton: some View {
        Button(action: start) {
            Text("Start session")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(red: 0.004, green: 0.125, blue: 0.094))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md + 4)
                .background(Theme.accent)
                .cornerRadius(Radius.lg)
        }
    }

    private var recordingToggle: some View {
        Toggle(isOn: $session.recordSession) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Record this session")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("Captures the workout screen, your mic, and the coach audio.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textDim)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
        .padding(Spacing.md)
        .background(Theme.card)
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(session.recordSession ? Theme.accent : Theme.border, lineWidth: 1)
        )
    }

    private func start() {
        session.exercise = selected
        session.targetReps = reps
        session.goWorkout()
    }

    private func label(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 13, weight: .medium))
            .tracking(1)
            .foregroundColor(Theme.textDim)
    }

    private func exerciseRow(_ id: ExerciseId, subtitle: String) -> some View {
        let active = selected == id
        return Button(action: { selected = id }) {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(id.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(active ? Theme.accent : Theme.text)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textDim)
                }
                Spacer(minLength: 0)
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.accent)
                        .font(.system(size: 20))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(active ? Theme.bgElevated : Theme.card)
            .cornerRadius(Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(active ? Theme.accent : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
