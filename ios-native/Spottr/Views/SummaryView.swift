import AVKit
import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var session: SessionState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let summary = session.summary {
                    Text(summary.mode == .hype
                         ? "Motivation session"
                         : "\(summary.exercise.displayName) set")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                        .padding(.bottom, Spacing.md)

                    HStack(spacing: Spacing.sm) {
                        if summary.mode == .hype {
                            // No rep target or form scoring in a hype session.
                            stat("TIME", formatDuration(ms: summary.durationMs), accent: true)
                        } else {
                            stat("REPS", "\(summary.reps)")
                            stat("AVG SCORE",
                                 "\(Int(summary.avgScore * 100))",
                                 accent: summary.avgScore >= 0.75)
                            stat("TIME", formatDuration(ms: summary.durationMs))
                        }
                    }

                    if summary.mode == .form {
                        section("TOP ISSUES") {
                            if summary.topIssues.isEmpty {
                                Text("No major issues — clean set.")
                                    .foregroundColor(Theme.textDim)
                            } else {
                                ForEach(summary.topIssues, id: \.self) { id in
                                    HStack(spacing: Spacing.sm) {
                                        Circle().fill(Theme.warn).frame(width: 8, height: 8)
                                        Text(id.label)
                                            .font(.system(size: 16))
                                            .foregroundColor(Theme.text)
                                    }
                                }
                            }
                        }
                    }

                    section(summary.mode == .hype ? "NEXT TIME" : "NEXT SET") {
                        Text(summary.recommendation)
                            .font(.system(size: 16))
                            .foregroundColor(Theme.text)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                            .background(Theme.card)
                            .cornerRadius(Radius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )
                    }

                    if let recordingURL = summary.recordingURL {
                        section("RECORDING") {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                VideoPlayer(player: AVPlayer(url: recordingURL))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                                    .background(Color.black)
                                    .cornerRadius(Radius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.md)
                                            .strokeBorder(Theme.border, lineWidth: 1)
                                    )
                                Text(recordingURL.lastPathComponent)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                    .lineLimit(1)
                                Text(summary.recordingPhotoSaveState.summaryText)
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textDim)
                                ShareLink(item: recordingURL) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Share recording")
                                    }
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(Color(red: 0.004, green: 0.125, blue: 0.094))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Spacing.md)
                                    .background(Theme.accent)
                                    .cornerRadius(Radius.md)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.md)
                            .background(Theme.card)
                            .cornerRadius(Radius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )
                        }
                    }
                } else {
                    Text("No set data — start a new set.")
                        .foregroundColor(Theme.textDim)
                        .padding(.top, Spacing.xl)
                }

                Spacer(minLength: Spacing.lg)

                Button(action: { session.startNewSet() }) {
                    Text(session.summary?.mode == .hype ? "Go again" : "Start next set")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.004, green: 0.125, blue: 0.094))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md + 2)
                        .background(Theme.accent)
                        .cornerRadius(Radius.lg)
                }
                Button(action: { session.popToHome() }) {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md + 2)
                        .background(Theme.card)
                        .cornerRadius(Radius.lg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                }
            }
            .padding(Spacing.lg)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Set summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium)).tracking(1).foregroundColor(Theme.textDim)
            Text(value).font(.system(size: 32, weight: .bold)).foregroundColor(accent ? Theme.accent : Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Theme.card)
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.system(size: 13, weight: .medium)).tracking(1)
                .foregroundColor(Theme.textDim)
            content()
        }
        .padding(.top, Spacing.lg)
    }

    private func formatDuration(ms: Int) -> String {
        let total = ms / 1000
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
