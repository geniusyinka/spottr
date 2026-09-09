import SwiftUI

struct HomeView: View {
    @EnvironmentObject var session: SessionState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Spottr")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text("AI gym coach. Real-time form feedback.")
                        .font(.system(size: 17))
                        .foregroundColor(Theme.textDim)
                }
                .padding(.top, Spacing.xl)

                nameField

                HStack(spacing: Spacing.sm) {
                    Button(action: { session.goExerciseSelect() }) {
                        Text("Start a set")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(red: 0.004, green: 0.125, blue: 0.094))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .padding(.horizontal, Spacing.sm)
                            .background(Theme.accent)
                            .cornerRadius(Radius.lg)
                    }
                    Button(action: { session.startHypeSession() }) {
                        Text("Just pure motivation")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.text)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .padding(.horizontal, Spacing.sm)
                            .background(Theme.card)
                            .cornerRadius(Radius.lg)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.lg)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Spacing.sm)

                disclaimerCard
            }
            .padding(Spacing.lg)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("YOUR NAME")
                .font(.system(size: 12, weight: .medium))
                .tracking(1)
                .foregroundColor(Theme.textDim)
            TextField("Your name", text: $session.athleteName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.text)
                .padding(Spacing.md)
                .background(Theme.card)
                .cornerRadius(Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        }
        .padding(.top, Spacing.md)
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("BEFORE YOU START")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundColor(Theme.warn)
            Group {
                Text("Spottr is a prototype, not medical or professional coaching advice. Form analysis is heuristic and may be wrong.")
                Text("Stop immediately if you feel pain, dizziness, or instability. Consult a qualified coach or physician before starting a new program.")
                Text("Video frames are processed on-device and never recorded by default.")
            }
            .font(.system(size: 14))
            .foregroundColor(Theme.textDim)
            .lineSpacing(4)
        }
        .padding(Spacing.md)
        .background(Theme.card)
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}
