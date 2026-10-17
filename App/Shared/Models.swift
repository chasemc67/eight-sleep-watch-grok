import Foundation

enum EightSleepError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited
    case badStatus(Int, String)
    case noDevice
    case notSignedIn
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "That email or password was rejected."
        case .rateLimited:
            return "Eight Sleep is rate limiting sign-in. Wait a minute and try again."
        case .badStatus(let code, let detail):
            return detail.isEmpty ? "Eight Sleep returned \(code)." : "Eight Sleep returned \(code). \(detail)"
        case .noDevice:
            return "No Eight Sleep device is on this account."
        case .notSignedIn:
            return "Sign in on iPhone first."
        case .message(let text):
            return text
        }
    }
}

struct TokenResponse: Decodable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int
    var userId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case userId
        case userID = "user_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        if let seconds = try? container.decode(Int.self, forKey: .expiresIn) {
            expiresIn = seconds
        } else if let seconds = try? container.decode(Double.self, forKey: .expiresIn) {
            expiresIn = Int(seconds)
        } else {
            expiresIn = 3600
        }
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
            ?? container.decodeIfPresent(String.self, forKey: .userID)
    }
}

struct UserRecord: Equatable {
    var userId: String?
    var firstName: String?
    var lastName: String?
    var email: String?
    var devices: [String]?
    var currentDeviceId: String?
    var side: String?

    init(
        userId: String?,
        firstName: String?,
        lastName: String?,
        email: String?,
        devices: [String]? = nil,
        currentDeviceId: String? = nil,
        side: String? = nil
    ) {
        self.userId = userId
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.devices = devices
        self.currentDeviceId = currentDeviceId
        self.side = side
    }
}

extension UserRecord: Decodable {
    enum CodingKeys: String, CodingKey {
        case userId, firstName, lastName, email, devices, currentDevice
    }

    enum DeviceKeys: String, CodingKey {
        case id, side
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        devices = try container.decodeIfPresent([String].self, forKey: .devices)
        currentDeviceId = nil
        side = nil
        if let device = try? container.nestedContainer(keyedBy: DeviceKeys.self, forKey: .currentDevice) {
            currentDeviceId = try device.decodeIfPresent(String.self, forKey: .id)
            side = try device.decodeIfPresent(String.self, forKey: .side)
        }
    }
}

struct UserEnvelope: Decodable {
    var user: UserRecord
}

struct DeviceSides: Equatable {
    var leftUserId: String?
    var rightUserId: String?
    var awayUserIds: Set<String>

    init(leftUserId: String?, rightUserId: String?, awayUserIds: Set<String>) {
        self.leftUserId = leftUserId
        self.rightUserId = rightUserId
        self.awayUserIds = awayUserIds
    }
}

extension DeviceSides: Decodable {
    enum CodingKeys: String, CodingKey {
        case leftUserId, rightUserId, awaySides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leftUserId = try container.decodeIfPresent(String.self, forKey: .leftUserId)
        rightUserId = try container.decodeIfPresent(String.self, forKey: .rightUserId)
        if let away = try? container.decode([String: String].self, forKey: .awaySides) {
            awayUserIds = Set(away.values.filter { !$0.isEmpty })
        } else {
            awayUserIds = []
        }
    }
}

struct DeviceEnvelope: Decodable {
    var result: DeviceSides
}

struct TemperatureStatus: Equatable {
    var currentLevel: Int?
    var stateType: String?

    var isOn: Bool {
        guard let stateType else { return false }
        return stateType != "off"
    }
}

extension TemperatureStatus: Decodable {
    enum CodingKeys: String, CodingKey {
        case currentLevel, currentState
    }

    struct State: Decodable {
        var type: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let level = try? container.decode(Int.self, forKey: .currentLevel) {
            currentLevel = level
        } else if let level = try? container.decode(Double.self, forKey: .currentLevel) {
            currentLevel = Int(level.rounded())
        } else {
            currentLevel = nil
        }
        stateType = try container.decodeIfPresent(State.self, forKey: .currentState)?.type
    }
}

struct BedSide: Identifiable, Equatable {
    enum Side: String, Codable, CaseIterable {
        case left
        case right

        var title: String { rawValue.capitalized }
    }

    var side: Side
    var userId: String?
    var name: String
    var isAway: Bool
    var level: Int?
    var isOn: Bool?

    var id: String { side.rawValue }
    var canControl: Bool { userId?.isEmpty == false }
}

struct BedSnapshot {
    var deviceId: String
    var accountUserId: String
    var sides: [BedSide]
}

enum SideName {
    static func display(first: String?, last: String?, email: String?) -> String {
        let parts = [first, last]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }
        if let email {
            let local = email.split(separator: "@").first.map(String.init) ?? ""
            if !local.isEmpty { return local }
        }
        return "Sleeper"
    }
}

enum BedAssembler {
    static func sides(device: DeviceSides, profiles: [String: UserRecord]) -> [BedSide] {
        let slots: [(BedSide.Side, String?)] = [
            (.left, device.leftUserId),
            (.right, device.rightUserId)
        ]
        return slots.map { side, rawId in
            let userId = rawId?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let userId, !userId.isEmpty else {
                return BedSide(side: side, userId: nil, name: "Empty", isAway: false, level: nil, isOn: nil)
            }
            let profile = profiles[userId]
            let away = device.awayUserIds.contains(userId) || profile?.side == "away"
            return BedSide(
                side: side,
                userId: userId,
                name: SideName.display(first: profile?.firstName, last: profile?.lastName, email: profile?.email),
                isAway: away,
                level: nil,
                isOn: nil
            )
        }
    }
}

struct StoredSession: Codable, Equatable {
    var email: String
    var password: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var userId: String
    var deviceId: String
    var selectedSide: String?
    var selectedUserId: String?
    var selectedName: String?
    var lastLevel: Int?
    var lastIsOn: Bool?

    init(email: String, password: String, token: TokenResponse) throws {
        guard let userId = token.userId, !userId.isEmpty else {
            throw EightSleepError.message("Eight Sleep did not return a user id.")
        }
        self.email = email
        self.password = password
        self.accessToken = token.accessToken
        self.refreshToken = token.refreshToken
        self.expiresAt = Date().addingTimeInterval(TimeInterval(max(token.expiresIn, 60)))
        self.userId = userId
        self.deviceId = ""
        self.selectedSide = nil
        self.selectedUserId = nil
        self.selectedName = nil
        self.lastLevel = nil
        self.lastIsOn = nil
    }

    init(
        email: String,
        password: String,
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date,
        userId: String,
        deviceId: String,
        selectedSide: String?,
        selectedUserId: String?,
        selectedName: String?,
        lastLevel: Int?,
        lastIsOn: Bool?
    ) {
        self.email = email
        self.password = password
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
        self.deviceId = deviceId
        self.selectedSide = selectedSide
        self.selectedUserId = selectedUserId
        self.selectedName = selectedName
        self.lastLevel = lastLevel
        self.lastIsOn = lastIsOn
    }

    func applying(_ token: TokenResponse) -> StoredSession {
        var copy = self
        copy.accessToken = token.accessToken
        if let refresh = token.refreshToken, !refresh.isEmpty {
            copy.refreshToken = refresh
        }
        if let userId = token.userId, !userId.isEmpty {
            copy.userId = userId
        }
        let lifetime = TimeInterval(max(token.expiresIn, 60))
        copy.expiresAt = Date().addingTimeInterval(lifetime)
        return copy
    }

    var needsRefresh: Bool {
        Date().addingTimeInterval(AppConfig.tokenFreshnessBuffer) >= expiresAt
    }
}
