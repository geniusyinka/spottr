import Foundation

/// Events the client pushes through the Realtime data channel as `conversation.item.create`
/// messages with role=user, prefixed with "[event]".
enum CoachEvent: Encodable {
    /// Camera has locked onto the athlete; the coach should greet briefly.
    case setReady(exercise: ExerciseId, targetReps: Int?)
    case setStarted(exercise: ExerciseId, targetReps: Int?)
    case repCompleted(RepCompleted)
    case formIssue(exercise: ExerciseId, issue: FormIssueId, severity: IssueSeverity)
    case setFinished(exercise: ExerciseId, reps: Int, avgScore: Double, durationMs: Int, topIssues: [FormIssueId])
    case coachShouldSpeak(reason: String)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Date().timeIntervalSince1970 * 1000, forKey: .timestamp)
        switch self {
        case .setReady(let exercise, let target):
            try c.encode("set_ready", forKey: .type)
            try c.encode(exercise, forKey: .exercise)
            try c.encodeIfPresent(target, forKey: .targetReps)
        case .setStarted(let exercise, let target):
            try c.encode("set_started", forKey: .type)
            try c.encode(exercise, forKey: .exercise)
            try c.encodeIfPresent(target, forKey: .targetReps)
        case .repCompleted(let rep):
            try c.encode("rep_completed", forKey: .type)
            try c.encode(rep, forKey: .rep)
        case .formIssue(let exercise, let issue, let severity):
            try c.encode("form_issue", forKey: .type)
            try c.encode(exercise, forKey: .exercise)
            try c.encode(issue, forKey: .issue)
            try c.encode(severity, forKey: .severity)
        case .setFinished(let exercise, let reps, let avg, let dur, let issues):
            try c.encode("set_finished", forKey: .type)
            try c.encode(exercise, forKey: .exercise)
            try c.encode(reps, forKey: .reps)
            try c.encode(avg, forKey: .avgScore)
            try c.encode(dur, forKey: .durationMs)
            try c.encode(issues, forKey: .topIssues)
        case .coachShouldSpeak(let reason):
            try c.encode("coach_should_speak", forKey: .type)
            try c.encode(reason, forKey: .reason)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, timestamp, exercise, targetReps, rep, issue, severity
        case reps, avgScore, durationMs, topIssues, reason
    }
}

/// Build the JSON payload for `conversation.item.create` wrapping a coach event.
enum RealtimeEnvelope {
    static func conversationItem(for event: CoachEvent) throws -> Data {
        let json = try JSONEncoder().encode(event)
        let text = String(data: json, encoding: .utf8) ?? "{}"
        let payload: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": "[event] \(text)"
                    ]
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Trigger a turn. Per-response instructions are intentionally OMITTED so
    /// the model keeps the session-level coaching prompt for every cue.
    ///
    /// Uses the GA `output_modalities` field (legacy `modalities` is now
    /// rejected by the API).
    static func responseCreate() throws -> Data {
        let payload: [String: Any] = [
            "type": "response.create",
            "response": [
                "output_modalities": ["audio"]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    /// Cancel the in-flight response. Used when a fresher cue should win.
    /// The server replies with a final `response.done` (status: cancelled).
    static func responseCancel() throws -> Data {
        let payload: [String: Any] = ["type": "response.cancel"]
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
