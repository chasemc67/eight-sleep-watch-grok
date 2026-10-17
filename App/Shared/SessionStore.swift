import Foundation
import WatchConnectivity

/// Signed-in session for both apps. Secrets live in this device's Keychain.
/// The iPhone copies them to the watch with WatchConnectivity, because an App
/// Group container does not cross from phone to watch. Each side stores what
/// it receives in its own Keychain so the watch can keep working, and can
/// refresh, when the phone is out of reach.
@MainActor
final class SessionStore: NSObject, ObservableObject {
    @Published private(set) var session: StoredSession?
    @Published private(set) var sides: [BedSide] = []
    @Published private(set) var level: Int?
    @Published private(set) var isOn = false
    @Published private(set) var busy = false
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    @Published var emailDraft = ""
    @Published var passwordDraft = ""

    private let client = EightSleepClient()
    private var didStart = false
    private var sessionActivated = false
    private var dirty = false
    private var serverIsOn = false
    private var committedLevel: Int?
    private var debounce: Task<Void, Never>?
    private var sending = false
    private var sendAgain = false

    var selectedSide: BedSide.Side? {
        session?.selectedSide.flatMap(BedSide.Side.init(rawValue:))
    }

    var controlsEnabled: Bool {
        session?.selectedUserId?.isEmpty == false && level != nil
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        if let stored = KeychainStore.load() {
            session = stored
            level = stored.lastLevel
            committedLevel = stored.lastLevel
            isOn = stored.lastIsOn ?? false
            serverIsOn = isOn
            emailDraft = stored.email
        }
        activateConnectivity()
        Task {
            #if os(watchOS)
            if session?.selectedUserId != nil {
                await refreshTemperature()
            }
            #else
            if session != nil {
                await reloadBed()
            }
            #endif
        }
    }

    func signIn() async {
        let email = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordDraft
        guard email.contains("@"), !password.isEmpty else {
            errorMessage = "Enter the email and password for your Eight Sleep account."
            return
        }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let token = try await client.passwordGrant(email: email, password: password)
            var stored = try StoredSession(email: email, password: password, token: token)
            session = stored
            passwordDraft = ""
            persist()
            stored = try await client.ensureFresh(stored)
            session = stored
            let bed = try await authorized { token in
                try await self.client.loadBed(token: token)
            }
            applyBed(bed, push: true)
        } catch {
            session = nil
            KeychainStore.delete()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signOut() {
        debounce?.cancel()
        clearLocal()
        pushContext()
    }

    func reloadBed() async {
        guard session != nil else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let bed = try await authorized { token in
                try await self.client.loadBed(token: token)
            }
            applyBed(bed, push: true)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func choose(_ side: BedSide) {
        guard side.canControl, var stored = session, let userId = side.userId else { return }
        stored.selectedSide = side.side.rawValue
        stored.selectedUserId = userId
        stored.selectedName = side.name
        stored.lastLevel = side.level
        stored.lastIsOn = side.isOn
        session = stored
        level = side.level
        committedLevel = side.level
        isOn = side.isOn ?? false
        serverIsOn = isOn
        dirty = false
        errorMessage = nil
        persist()
        pushContext()
    }

    func warmer() { nudge(steps: 1) }
    func cooler() { nudge(steps: -1) }

    func refreshTemperature() async {
        guard let userId = session?.selectedUserId, !userId.isEmpty else { return }
        do {
            let status = try await authorized { token in
                try await self.client.temperature(userId: userId, token: token)
            }
            serverIsOn = status.isOn
            guard !dirty else { return }
            level = status.currentLevel
            committedLevel = status.currentLevel
            isOn = status.isOn
            if var stored = session {
                let changed = stored.lastLevel != status.currentLevel || stored.lastIsOn != status.isOn
                stored.lastLevel = status.currentLevel
                stored.lastIsOn = status.isOn
                session = stored
                persist()
                if changed { pushContext() }
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func nudge(steps: Int) {
        guard controlsEnabled, let current = level else {
            errorMessage = "Set up Eight Sleep Grok on your iPhone."
            return
        }
        level = LevelMath.applying(steps: steps, to: current)
        if !serverIsOn {
            isOn = true
        }
        dirty = true
        errorMessage = nil
        if sending {
            sendAgain = true
            return
        }
        debounce?.cancel()
        debounce = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: AppConfig.debounceNanoseconds)
            } catch {
                return
            }
            await self?.flushLevel()
        }
    }

    private func flushLevel() async {
        guard !sending else {
            sendAgain = true
            return
        }
        sending = true
        isSending = true
        defer {
            sending = false
            isSending = false
            if sendAgain {
                sendAgain = false
                Task { await self.flushLevel() }
            }
        }
        guard let userId = session?.selectedUserId, let target = level else { return }
        let shouldPower = !serverIsOn
        do {
            try await authorized { token in
                if shouldPower {
                    try await self.client.turnOn(userId: userId, token: token)
                }
                try await self.client.setLevel(userId: userId, level: target, token: token)
            }
            serverIsOn = true
            isOn = true
            committedLevel = target
            if level == target && !sendAgain {
                dirty = false
            } else {
                sendAgain = true
            }
            if var stored = session {
                stored.lastLevel = target
                stored.lastIsOn = true
                session = stored
                persist()
                pushContext()
            }
            errorMessage = nil
        } catch {
            if sendAgain { return }
            level = committedLevel
            isOn = serverIsOn
            dirty = false
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applyBed(_ bed: BedSnapshot, push: Bool) {
        sides = bed.sides
        guard var stored = session else { return }
        stored.deviceId = bed.deviceId
        if stored.selectedSide == nil {
            let owned = bed.sides.first { $0.userId == stored.userId && $0.canControl }
            let fallback = bed.sides.first { $0.canControl }
            if let match = owned ?? fallback {
                stored.selectedSide = match.side.rawValue
                stored.selectedUserId = match.userId
                stored.selectedName = match.name
                stored.lastLevel = match.level
                stored.lastIsOn = match.isOn
                level = match.level
                committedLevel = match.level
                isOn = match.isOn ?? false
                serverIsOn = isOn
                dirty = false
            }
        } else if let match = bed.sides.first(where: { $0.side.rawValue == stored.selectedSide }) {
            stored.selectedUserId = match.userId
            stored.selectedName = match.name
            if !dirty {
                stored.lastLevel = match.level
                stored.lastIsOn = match.isOn
                level = match.level
                committedLevel = match.level
                isOn = match.isOn ?? false
                serverIsOn = isOn
            }
        }
        session = stored
        persist()
        if push { pushContext() }
    }

    private func authorized<T>(_ work: (String) async throws -> T) async throws -> T {
        guard var stored = session else { throw EightSleepError.notSignedIn }
        do {
            stored = try await client.ensureFresh(stored)
            session = stored
            persist()
            return try await work(stored.accessToken)
        } catch EightSleepError.unauthorized {
            stored = try await client.forceRefresh(stored)
            session = stored
            persist()
            pushContext()
            return try await work(stored.accessToken)
        }
    }

    private func persist() {
        guard let session else { return }
        try? KeychainStore.save(session)
        writeAppGroup()
    }

    private func clearLocal() {
        session = nil
        sides = []
        level = nil
        committedLevel = nil
        isOn = false
        serverIsOn = false
        dirty = false
        sendAgain = false
        errorMessage = nil
        passwordDraft = ""
        KeychainStore.delete()
        guard let defaults = UserDefaults(suiteName: AppConfig.appGroup),
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup) != nil
        else { return }
        defaults.removeObject(forKey: "selectedSide")
        defaults.removeObject(forKey: "selectedName")
        defaults.removeObject(forKey: "lastLevel")
        defaults.removeObject(forKey: "lastIsOn")
    }

    private func writeAppGroup() {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup) != nil,
              let defaults = UserDefaults(suiteName: AppConfig.appGroup) else { return }
        defaults.set(session?.selectedSide, forKey: "selectedSide")
        defaults.set(session?.selectedName, forKey: "selectedName")
        if let level = session?.lastLevel {
            defaults.set(level, forKey: "lastLevel")
        }
        if let isOn = session?.lastIsOn {
            defaults.set(isOn, forKey: "lastIsOn")
        }
    }

    private func activateConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func pushContext() {
        guard WCSession.isSupported(), sessionActivated else { return }
        let connectivity = WCSession.default
        guard connectivity.activationState == .activated else { return }
        do {
            try connectivity.updateApplicationContext(syncPayload())
        } catch {
            // The counterpart may be unpaired or busy. The Keychain copy remains.
        }
    }

    private func syncPayload() -> [String: Any] {
        guard let session else { return ["signedIn": false] }
        var payload: [String: Any] = [
            "signedIn": true,
            "email": session.email,
            "password": session.password,
            "accessToken": session.accessToken,
            "expiresAt": session.expiresAt.timeIntervalSince1970,
            "userId": session.userId,
            "deviceId": session.deviceId
        ]
        if let refresh = session.refreshToken { payload["refreshToken"] = refresh }
        if let side = session.selectedSide { payload["selectedSide"] = side }
        if let userId = session.selectedUserId { payload["selectedUserId"] = userId }
        if let name = session.selectedName { payload["selectedName"] = name }
        if let level = session.lastLevel { payload["lastLevel"] = level }
        if let on = session.lastIsOn { payload["lastIsOn"] = on }
        return payload
    }

    private func applyRemote(_ remote: RemoteSession) {
        guard remote.signedIn else {
            clearLocal()
            return
        }
        guard let incoming = remote.storedSession() else { return }
        let localDirty = dirty
        let previousUser = session?.selectedUserId
        if var current = session, current.expiresAt > incoming.expiresAt {
            current.selectedSide = incoming.selectedSide ?? current.selectedSide
            current.selectedUserId = incoming.selectedUserId ?? current.selectedUserId
            current.selectedName = incoming.selectedName ?? current.selectedName
            current.deviceId = incoming.deviceId.isEmpty ? current.deviceId : incoming.deviceId
            if !localDirty {
                current.lastLevel = incoming.lastLevel ?? current.lastLevel
                current.lastIsOn = incoming.lastIsOn ?? current.lastIsOn
            }
            session = current
        } else {
            var merged = incoming
            if localDirty, let current = session {
                merged.lastLevel = current.lastLevel
                merged.lastIsOn = current.lastIsOn
            }
            session = merged
        }
        if !localDirty {
            level = session?.lastLevel
            committedLevel = level
            isOn = session?.lastIsOn ?? false
            serverIsOn = isOn
        }
        persist()
        let userChanged = previousUser != session?.selectedUserId
        if !localDirty && (userChanged || (session?.selectedUserId != nil && level == nil)) {
            Task { await self.refreshTemperature() }
        }
        #if os(iOS)
        if let userId = session?.selectedUserId, let last = session?.lastLevel,
           let index = sides.firstIndex(where: { $0.userId == userId }) {
            sides[index].level = last
            sides[index].isOn = session?.lastIsOn
        }
        #endif
    }
}

private struct RemoteSession: Sendable {
    var signedIn: Bool
    var email: String?
    var password: String?
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?
    var userId: String?
    var deviceId: String?
    var selectedSide: String?
    var selectedUserId: String?
    var selectedName: String?
    var lastLevel: Int?
    var lastIsOn: Bool?

    init?(_ raw: [String: Any]) {
        guard raw.keys.contains("signedIn") else { return nil }
        signedIn = (raw["signedIn"] as? Bool) ?? ((raw["signedIn"] as? NSNumber)?.boolValue ?? false)
        email = raw["email"] as? String
        password = raw["password"] as? String
        accessToken = raw["accessToken"] as? String
        refreshToken = raw["refreshToken"] as? String
        if let seconds = raw["expiresAt"] as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: seconds)
        } else if let seconds = raw["expiresAt"] as? NSNumber {
            expiresAt = Date(timeIntervalSince1970: seconds.doubleValue)
        }
        userId = raw["userId"] as? String
        deviceId = raw["deviceId"] as? String
        selectedSide = raw["selectedSide"] as? String
        selectedUserId = raw["selectedUserId"] as? String
        selectedName = raw["selectedName"] as? String
        lastLevel = raw["lastLevel"] as? Int ?? (raw["lastLevel"] as? NSNumber)?.intValue
        if let on = raw["lastIsOn"] as? Bool {
            lastIsOn = on
        } else if let on = raw["lastIsOn"] as? NSNumber {
            lastIsOn = on.boolValue
        }
    }

    func storedSession() -> StoredSession? {
        guard signedIn,
              let email, let password, let accessToken, let expiresAt, let userId
        else { return nil }
        return StoredSession(
            email: email,
            password: password,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId,
            deviceId: deviceId ?? "",
            selectedSide: selectedSide,
            selectedUserId: selectedUserId,
            selectedName: selectedName,
            lastLevel: lastLevel,
            lastIsOn: lastIsOn
        )
    }
}

extension SessionStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let remote = RemoteSession(session.receivedApplicationContext)
        let activated = activationState == .activated
        Task { @MainActor in
            self.sessionActivated = activated
            guard activated else { return }
            if let remote {
                self.applyRemote(remote)
            }
            if self.session != nil {
                self.pushContext()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let remote = RemoteSession(applicationContext) else { return }
        Task { @MainActor in
            self.applyRemote(remote)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
