import Foundation

/// Events the client pushes through the Realtime data channel as `conversation.item.create`
/// messages with role=user, prefixed with "[event]".
enum CoachEvent: Encodable {
    /// The athlete is now fully in frame and ready; the coach should greet.
    case setReady(exercise: ExerciseId, targetReps: Int?, framing: String, fullBodyVisible: Bool)
    case setStarted(exercise: ExerciseId, targetReps: Int?)
    /// Latest camera-derived pose context. This is sent silently so the coach
    /// can answer user questions from current visual data.
    case cameraObservation(CameraObservation)
    /// Latest real vision-model description from a camera snapshot.
    case visualObservation(VisualObservation)
    case repCompleted(RepCompleted)
    case formIssue(exercise: ExerciseId, issue: FormIssueId, severity: IssueSeverity)
    case setFinished(exercise: ExerciseId, reps: Int, avgScore: Double, durationMs: Int, topIssues: [FormIssueId])
    case coachShouldSpeak(reason: String)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Date().timeIntervalSince1970 * 1000, forKey: .timestamp)
        switch self {
        case .setReady(let exercise, let target, let framing, let fullBodyVisible):
            try c.encode("set_ready", forKey: .type)
            try c.encode(exercise, forKey: .exercise)
            try c.encodeIfPresent(target, forKey: .targetReps)
            try c.encode(framing, forKey: .framing)
            try c.encode(fullBodyVisible, forKey: .fullBodyVisible)
        case .setStarted(let exercise, let target):
            try c.encode("set_started", forKey: .type)
            try c.encode(exercise, forKey: .exercise)
            try c.encodeIfPresent(target, forKey: .targetReps)
        case .cameraObservation(let observation):
            try c.encode("camera_observation", forKey: .type)
            try c.encode(observation, forKey: .observation)
        case .visualObservation(let observation):
            try c.encode("visual_observation", forKey: .type)
            try c.encode(observation, forKey: .observation)
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
        case type, timestamp, exercise, targetReps, observation, rep, issue, severity
        case reps, avgScore, durationMs, topIssues, reason
        case framing, fullBodyVisible
    }
}

struct CameraObservation: Encodable {
    let exercise: ExerciseId
    let workoutStage: String
    let targetReps: Int
    let reps: Int
    let phase: RepPhase
    let activeIssues: [FormIssueId]
    let poseVisible: Bool
    let fullBodyVisible: Bool
    let framing: String
    let bodyBox: BodyBox?
    let avgConfidence: Double?
    let visibleKeypoints: [String]
    let keypoints: [PoseLandmark]
}

struct BodyBox: Encodable {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double
}

struct PoseLandmark: Encodable {
    let name: String
    let x: Double
    let y: Double
    let confidence: Double
}

struct VisualObservation: Encodable {
    let exercise: ExerciseId
    let workoutStage: String
    let reps: Int
    let description: String
    let facts: VisionFacts?
    let model: String
    let capturedAt: Int
    let analyzedAt: Int?
    let receivedAt: Int
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
