import Foundation

/// Backend URL the app calls to mint Realtime ephemeral keys. iOS Simulator
/// shares the host network, so localhost works there. On a physical device
/// the phone must reach this URL on the LAN — change to your Mac's IP.
enum BackendConfig {
    /// Production backend on Vercel. Override at build time by setting
    /// `SpottrBackendURL` in Info.plist (e.g. for local `vercel dev` testing).
    static let baseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SpottrBackendURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://spottr-yunggenius-projects.vercel.app")!
    }()
}

struct EphemeralSession: Decodable {
    let sessionId: String?
    let clientSecret: String
    let expiresAt: Int?
    let model: String
    let voice: String
}

enum BackendClient {
    /// POST /api/realtime/session — returns a short-lived ephemeral key the app
    /// uses to open a WebRTC connection directly to OpenAI Realtime.
    static func createRealtimeSession(exercise: ExerciseId,
                                      targetReps: Int?,
                                      athleteName: String?) async throws -> EphemeralSession {
        var req = URLRequest(url: BackendConfig.baseURL.appending(path: "/api/realtime/session"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["exercise": exercise.rawValue]
        if let t = targetReps { body["targetReps"] = t }
        if let n = athleteName, !n.isEmpty { body["athleteName"] = n }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "BackendClient", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Session HTTP error: \(txt)"])
        }
        return try JSONDecoder().decode(EphemeralSession.self, from: data)
    }
}
