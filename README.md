# Eight Sleep Grok

iPhone and Apple Watch app for Chase's Eight Sleep. The phone signs in and chooses a side of the bed. The watch is only temperature up and down for that side. A watch-face complication opens the watch app.

This uses the unofficial Eight Sleep client API. It is not an Eight Sleep product, and the API can change without notice.

## What the apps do

- **iPhone.** Email and password sign-in. Tokens, and the password needed to mint a new token, stay in the Keychain. After sign-in the phone shows the left and right sides, the name on each side when the API returns one, and the current heating level. Pick the side the watch should control.
- **Apple Watch.** A large level, with big minus and plus buttons. Taps move the level by 10 (clamped to -100…100) immediately. Rapid taps wait 450ms and then send one update. If that side is off, the update turns it on (`currentState.type = smart`) and then sets `currentLevel`.
- **Complication.** Accessory circular, corner, and inline. Tapping it launches the watch app. It does not read or change the bed.

The phone copies the session to the watch with WatchConnectivity. An App Group does not cross from iPhone to Apple Watch, so each device keeps its own Keychain copy and can refresh on its own. The App Group `group.com.chasemc67.eightsleepwatch.grok` stores the non-secret side and level on each device.

Approximate Fahrenheit under the level uses the raw-level map from pyEight. The number the buttons change is the API level, not degrees.

## API

Eight Sleep does not publish this API. The calls below are what current open-source clients use.

### Sources

- [lukas-clarke/pyEight](https://github.com/lukas-clarke/pyEight) — OAuth client, device and user discovery, heating level, and side power. Client id and secret are `KNOWN_CLIENT_ID` / `KNOWN_CLIENT_SECRET` in `pyeight/constants.py`. Auth and device lookup are in `pyeight/eight.py` (`_get_auth`, `fetch_device_list`, `assign_users`). Temperature is in `pyeight/user.py` (`get_current_heating_level`, `set_heating_level`, `turn_on_side`, `turn_off_side`). The Fahrenheit table is `RAW_TO_FAHRENHEIT_MAP` in `pyeight/constants.py` (MIT).
- [lukas-clarke/eight_sleep](https://github.com/lukas-clarke/eight_sleep) — Home Assistant integration. Side names use `user.firstName` (`custom_components/eight_sleep/__init__.py`).
- [mezz64/pyEight](https://github.com/mezz64/pyEight) — the earlier library the original Home Assistant integration was built on.
- [steipete/eightctl](https://github.com/steipete/eightctl) — Go client. Password grant in `internal/client/auth.go`. Turn on then set level in `internal/client/temperature.go`. Side user ids in `internal/client/device.go`. `internal/client/device_sides_away_test.go` shows why the device request must pass `filter=leftUserId,rightUserId,awaySides`: an unfiltered device payload omits those fields when both sides are away.
- [atthewm/eightsleep-client](https://github.com/atthewm/eightsleep-client) — notes that the access token lasts about an hour and a refresh token is often missing, so clients sign in again with the password.
- [Dbochman/dotfiles `8sleep-api.py`](https://github.com/Dbochman/dotfiles/blob/main/openclaw/skills/8sleep/8sleep-api.py) — `grant_type=refresh_token` against the same token URL. The refresh response may omit `userId`, so the previous id is kept. If refresh fails, it falls back to the password grant.
- [api-evangelist/eight-sleep](https://github.com/api-evangelist/eight-sleep) — community OpenAPI writeups of the auth and temperature routes.

The client id `0894c7f33bb94800a03f1f4df13a4f38` and client secret shipped in this repo are those public mobile-app credentials. They are not a user secret. The account password is never written into the repo.

### Endpoints this app calls

| | |
| --- | --- |
| `POST https://auth-api.8slp.net/v1/tokens` | Password grant (`grant_type`, `username`, `password`, `client_id`, `client_secret`) and, when a refresh token was issued, `grant_type=refresh_token`. JSON body, `User-Agent: okhttp/4.9.3`. Response fields used: `access_token`, `expires_in`, `userId`, optional `refresh_token`. |
| `GET https://client-api.8slp.net/v1/users/me` | Signed-in user. `user.userId`, `user.devices`, `user.currentDevice.id`, `user.firstName`, `user.lastName`. |
| `GET https://client-api.8slp.net/v1/devices/{deviceId}?filter=leftUserId,rightUserId,awaySides` | Which user id is on the left and right. `awaySides` values are user ids currently away. |
| `GET https://client-api.8slp.net/v1/users/{userId}` | Name and `currentDevice.side` for that person. |
| `GET https://app-api.8slp.net/v1/users/{userId}/temperature` | `currentLevel` (-100…100) and `currentState.type` (`smart` is on, `off` is off). |
| `PUT https://app-api.8slp.net/v1/users/{userId}/temperature` | `{"currentState":{"type":"smart"}}` turns the side on. `{"currentLevel":<level>}` sets the level. |

Temperature is addressed by the user id on that side, not by the words "left" or "right". A 401 retries once after a refresh. The level PUT does not send pyEight's follow-up `timeBased` body with `durationSeconds: 0`, because a zero duration can clear the setpoint. `increment_heating_level` in pyEight and `SetTemperatureForUser` in eightctl both write `currentLevel` on its own.

## Project

| | |
| --- | --- |
| Display name | Eight Sleep Grok |
| iPhone | `com.chasemc67.eightsleepwatch.grok` |
| watchOS | `com.chasemc67.eightsleepwatch.grok.watchkitapp` |
| Complication | `com.chasemc67.eightsleepwatch.grok.watchkitapp.widget` |
| App Group | `group.com.chasemc67.eightsleepwatch.grok` |
| Team | `XPU32D9V4J` |

The complication's bundle id has to start with the watch app's id, because it is embedded in the watch app.

XcodeGen spec is `project.yml`. The generated `EightSleepGrok.xcodeproj` is committed.

```sh
xcodegen generate
xcodebuild -scheme EightSleepGrok -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Archive with automatic signing. Run `~/bin/unlock-keychain.sh` before `xcodebuild` on this Mac mini so codesign can see the login keychain. Pass `-allowProvisioningUpdates` and the App Store Connect API key (`~/.appstoreconnect/private_keys/AuthKey_HNMF6F3W8B.p8`, key id `HNMF6F3W8B`). Export options are `Config/ExportOptions.plist`.
