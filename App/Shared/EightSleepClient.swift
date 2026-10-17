import Foundation

/// Unofficial Eight Sleep client.
///
/// Auth is the OAuth password grant at auth-api.8slp.net, then a refresh_token
/// grant when the token response included one, otherwise the password grant
/// again. Device sides come from client-api. Temperature reads and writes go
/// to app-api, per user id, which is how a side is addressed.
final class EightSleepClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 40
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func passwordGrant(email: String, password: String) async throws -> TokenResponse {
        let body: [String: String] = [
            "client_id": AppConfig.clientID,
            "client_secret": AppConfig.clientSecret,
            "grant_type": "password",
            "username": email,
            "password": password
        ]
        return try await tokenRequest(body)
    }

    func ensureFresh(_ stored: StoredSession) async throws -> StoredSession {
        stored.needsRefresh ? try await forceRefresh(stored) : stored
    }

    func forceRefresh(_ stored: StoredSession) async throws -> StoredSession {
        if let refresh = stored.refreshToken, !refresh.isEmpty {
            let body: [String: String] = [
                "client_id": AppConfig.clientID,
                "client_secret": AppConfig.clientSecret,
                "grant_type": "refresh_token",
                "refresh_token": refresh
            ]
            do {
                let token = try await tokenRequest(body)
                return stored.applying(token)
            } catch {
                // Refresh tokens are often absent or rejected. Fall through
                // to the password grant, which is what pyEight does.
            }
        }
        let token = try await passwordGrant(email: stored.email, password: stored.password)
        return stored.applying(token)
    }

    func loadBed(token: String) async throws -> BedSnapshot {
        let me = try await getUser(path: "users/me", token: token)
        guard let accountUserId = me.userId, !accountUserId.isEmpty else {
            throw EightSleepError.message("Eight Sleep did not return a user id.")
        }
        let deviceId = me.currentDeviceId ?? me.devices?.first
        guard let deviceId, !deviceId.isEmpty else {
            throw EightSleepError.noDevice
        }

        var components = URLComponents(
            url: url(AppConfig.clientAPI, "devices", deviceId),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "filter", value: "leftUserId,rightUserId,awaySides")
        ]
        guard let deviceURL = components?.url else {
            throw EightSleepError.message("Could not build the device URL.")
        }
        let device = try await send(url: deviceURL, method: "GET", body: nil, token: token, as: DeviceEnvelope.self).result

        var profiles: [String: UserRecord] = [:]
        if me.userId != nil {
            profiles[accountUserId] = me
        }
        let ids = [device.leftUserId, device.rightUserId]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for userId in Set(ids) where profiles[userId] == nil {
            profiles[userId] = try await getUser(path: "users/\(userId)", token: token)
        }

        var sides = BedAssembler.sides(device: device, profiles: profiles)
        for index in sides.indices {
            guard let userId = sides[index].userId else { continue }
            if let status = try? await temperature(userId: userId, token: token) {
                sides[index].level = status.currentLevel
                sides[index].isOn = status.isOn
            }
        }
        return BedSnapshot(deviceId: deviceId, accountUserId: accountUserId, sides: sides)
    }

    func temperature(userId: String, token: String) async throws -> TemperatureStatus {
        let endpoint = url(AppConfig.appAPI, "users", userId, "temperature")
        return try await send(url: endpoint, method: "GET", body: nil, token: token, as: TemperatureStatus.self)
    }

    func turnOn(userId: String, token: String) async throws {
        let endpoint = url(AppConfig.appAPI, "users", userId, "temperature")
        let body: [String: Any] = ["currentState": ["type": "smart"]]
        try await send(url: endpoint, method: "PUT", body: body, token: token)
    }

    func setLevel(userId: String, level: Int, token: String) async throws {
        let clamped = min(AppConfig.levelMaximum, max(AppConfig.levelMinimum, level))
        let endpoint = url(AppConfig.appAPI, "users", userId, "temperature")
        try await send(url: endpoint, method: "PUT", body: ["currentLevel": clamped], token: token)
    }

    private func getUser(path: String, token: String) async throws -> UserRecord {
        let parts = path.split(separator: "/").map(String.init)
        let endpoint = parts.reduce(AppConfig.clientAPI) { $0.appendingPathComponent($1) }
        return try await send(url: endpoint, method: "GET", body: nil, token: token, as: UserEnvelope.self).user
    }

    private func tokenRequest(_ body: [String: String]) async throws -> TokenResponse {
        try await send(url: AppConfig.authURL, method: "POST", body: body, token: nil, as: TokenResponse.self)
    }

    private func send<T: Decodable>(url: URL, method: String, body: Any?, token: String?, as type: T.Type) async throws -> T {
        let data = try await send(url: url, method: method, body: body, token: token)
        if data.isEmpty {
            throw EightSleepError.message("Eight Sleep returned an empty response.")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw EightSleepError.message("Could not read Eight Sleep's response.")
        }
    }

    @discardableResult
    private func send(url: URL, method: String, body: Any?, token: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("okhttp/4.9.3", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EightSleepError.message("Eight Sleep did not answer.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw EightSleepError.unauthorized
            }
            if http.statusCode == 429 {
                throw EightSleepError.rateLimited
            }
            let detail = Self.summarize(data)
            throw EightSleepError.badStatus(http.statusCode, detail)
        }
        return data
    }

    private func url(_ base: URL, _ parts: String...) -> URL {
        parts.reduce(base) { partial, part in
            partial.appendingPathComponent(part)
        }
    }

    static func summarize(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return "" }
        var summary = text
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message = (json["error_description"] as? String)
                ?? (json["message"] as? String)
                ?? (json["error"] as? String)
            if let message, !message.isEmpty {
                summary = message
            }
        }
        if summary.count > 180 {
            summary = String(summary.prefix(180))
        }
        return summary
    }
}
