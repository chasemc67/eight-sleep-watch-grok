import XCTest
@testable import EightSleepGrok

final class LevelMathTests: XCTestCase {
    func testStepAndClamp() {
        XCTAssertEqual(LevelMath.applying(steps: 1, to: 0), 10)
        XCTAssertEqual(LevelMath.applying(steps: -1, to: 0), -10)
        var level = 0
        for _ in 0..<5 {
            level = LevelMath.applying(steps: 1, to: level)
        }
        XCTAssertEqual(level, 50)
        XCTAssertEqual(LevelMath.applying(steps: 1, to: 95), 100)
        XCTAssertEqual(LevelMath.applying(steps: -1, to: -95), -100)
        XCTAssertEqual(LevelMath.levelText(20), "+20")
        XCTAssertEqual(LevelMath.levelText(0), "0")
        XCTAssertEqual(LevelMath.levelText(-10), "-10")
    }

    func testFahrenheitAnchors() {
        XCTAssertEqual(LevelMath.fahrenheit(for: -100), 55)
        XCTAssertEqual(LevelMath.fahrenheit(for: 20), 87)
        XCTAssertEqual(LevelMath.fahrenheit(for: 100), 111)
        XCTAssertEqual(LevelMath.fahrenheit(for: 0), 80.75, accuracy: 0.001)
        XCTAssertEqual(LevelMath.fahrenheitText(for: 20), "87°")
    }
}

final class DecodingTests: XCTestCase {
    func testTokenWithAndWithoutRefresh() throws {
        let withRefresh = Data(#"{"access_token":"abc","expires_in":3600,"userId":"u1","refresh_token":"r1"}"#.utf8)
        let token = try JSONDecoder().decode(TokenResponse.self, from: withRefresh)
        XCTAssertEqual(token.accessToken, "abc")
        XCTAssertEqual(token.refreshToken, "r1")
        XCTAssertEqual(token.userId, "u1")
        XCTAssertEqual(token.expiresIn, 3600)

        let without = Data(#"{"access_token":"abc","expires_in":120.5}"#.utf8)
        let refreshed = try JSONDecoder().decode(TokenResponse.self, from: without)
        XCTAssertNil(refreshed.refreshToken)
        XCTAssertNil(refreshed.userId)
        XCTAssertEqual(refreshed.expiresIn, 120)
    }

    func testTemperatureAndDeviceSides() throws {
        let temperature = Data(#"{"currentLevel":-10,"currentState":{"type":"off"}}"#.utf8)
        let status = try JSONDecoder().decode(TemperatureStatus.self, from: temperature)
        XCTAssertEqual(status.currentLevel, -10)
        XCTAssertFalse(status.isOn)

        let fractional = Data(#"{"currentLevel":10.6,"currentState":{"type":"smart"}}"#.utf8)
        let rounded = try JSONDecoder().decode(TemperatureStatus.self, from: fractional)
        XCTAssertEqual(rounded.currentLevel, 11)
        XCTAssertTrue(rounded.isOn)

        let deviceJSON = Data(
            #"{"result":{"leftUserId":"uid-a","rightUserId":"uid-b","awaySides":{"leftUserId":"uid-a","rightUserId":"uid-b"}}}"#.utf8
        )
        let device = try JSONDecoder().decode(DeviceEnvelope.self, from: deviceJSON).result
        let profiles = [
            "uid-a": UserRecord(userId: "uid-a", firstName: "A", lastName: nil, email: nil, side: "left"),
            "uid-b": UserRecord(userId: "uid-b", firstName: "B", lastName: "Side", email: "b@example.com", side: "right")
        ]
        let sides = BedAssembler.sides(device: device, profiles: profiles)
        XCTAssertEqual(sides.map(\.name), ["A", "B Side"])
        XCTAssertEqual(sides.map(\.side), [.left, .right])
        XCTAssertTrue(sides.allSatisfy(\.isAway))
        XCTAssertTrue(sides.allSatisfy(\.canControl))
    }

    func testEmptySideAndNameFallback() {
        let device = DeviceSides(leftUserId: "uid-a", rightUserId: " ", awayUserIds: [])
        let profiles = [
            "uid-a": UserRecord(userId: "uid-a", firstName: nil, lastName: nil, email: "chase@example.com", side: "left")
        ]
        let sides = BedAssembler.sides(device: device, profiles: profiles)
        XCTAssertEqual(sides[0].name, "chase")
        XCTAssertEqual(sides[1].name, "Empty")
        XCTAssertFalse(sides[1].canControl)
        XCTAssertEqual(SideName.display(first: nil, last: nil, email: nil), "Sleeper")
    }

    func testUserEnvelope() throws {
        let json = Data(
            #"{"user":{"userId":"uid-a","firstName":"Chase","lastName":"McCarty","email":"c@example.com","devices":["dev-1"],"currentDevice":{"id":"dev-1","side":"left"}}}"#.utf8
        )
        let user = try JSONDecoder().decode(UserEnvelope.self, from: json).user
        XCTAssertEqual(user.userId, "uid-a")
        XCTAssertEqual(user.currentDeviceId, "dev-1")
        XCTAssertEqual(user.side, "left")
        XCTAssertEqual(user.devices, ["dev-1"])
        XCTAssertEqual(SideName.display(first: user.firstName, last: user.lastName, email: user.email), "Chase McCarty")
    }
}
