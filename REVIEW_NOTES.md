# App Review Notes — MultiSet AR

Draft for the App Store Connect "Notes for Review" field. Keep it current.

---

## What the app does

MultiSet AR is a developer tool for MultiSet's Visual Positioning System. A
camera-equipped device recognises a previously scanned building and works out
exactly where it is, to within about five centimetres. Developers use the app to
verify their own maps on site and to publish an experience that visitors can open
by scanning a printed code.

## Please read first: why live positioning cannot be tested in Cupertino

**VPS localization requires physical presence inside a location that has already
been scanned and processed.** Pointing the camera at an unmapped room will
correctly report that it cannot find a position — the app is working, but there is
nothing to match against.

We know a reviewer cannot travel to a customer's warehouse, so the app ships with
three demos that run **anywhere, with no account and no network**, reachable from
the Home tab in two taps. They exercise the same code paths as production.

### Demo 1 — Track a printed target (recommended)

Works immediately on any desk.

1. Launch the app. Skip onboarding if it appears.
2. On **Home**, tap **Track a printed target**.
3. Tap **Get the printable target**, then **Export as PDF**.
4. Print it, or open the PDF full-screen on any second screen.
5. Tap **Start demo** and point the camera at the target from about 0.5 m.
6. An outline traces the target as you move around it.

### Demo 2 — Follow a demo route

1. On **Home**, tap **Follow a demo route** → **Start demo**.
2. Point the camera at the floor until a surface is found.
3. A three-metre route appears. Walk it.
4. The pathfinding, turn guidance, and path rendering are the production ones,
   running on a demo map instead of a real one. The UI labels it "Demo map".

### Demo 3 — Replay a recorded walk

1. On **Home**, tap **Replay a recorded walk** → **Start demo**.
2. A recorded frame sequence runs through the localization pipeline.
3. The pose readout shows position, rotation, confidence, and latency.

## Signing in

Nothing needed for the demos. To review the account-backed half:

```
Email:    <fill in before submission>
Password: <fill in before submission>
```

That account has maps, tracked objects, and a published experience.

Sign-in uses the same credentials as the MultiSet developer portal
(https://developer.multiset.ai/). Credentials go to the device keychain and are
sent only to `api.multiset.ai` to authenticate. The app then creates SDK
credentials for itself via the account API so the user never types a client
secret.

## App Clip

Invocation URL — tappable:

```
https://api.multiset.ai/space/<fill in before submission>
```

A QR encoding the same URL is attached to this submission.

The Clip shows a branded card describing what will happen, asks for camera
permission with that context on screen, then runs the AR session. It requires no
account. Every failure path is handled with a specific message: invalid code,
ended experience, location still processing, no network, camera denied, device
without ARKit, and expired session.

## Third-party content — Guideline 1.2

Experiences opened in the app are published by MultiSet's customers, which makes
this user-generated content.

- **Report:** every experience carries a **Report** action on its intro card, in
  both the app and the Clip, and **Settings → Legal → Report a hosted
  experience**.
- **Contact:** contact@multiset.ai, in-app in Settings.
- **Kill switch:** any experience can be disabled server-side immediately via
  `unpublish`; scanning a revoked code shows "This experience has ended". Whole
  accounts can be disabled the same way.
- **Moderation policy:** <link before submission>.

## Permissions

| Permission | Why | When asked |
|---|---|---|
| Camera | Required. Recognises surroundings to compute position. | On the intro card, with context — never cold |
| Location, when in use | Optional. Narrows which mapped area you are in. | Only if the map is georeferenced |
| Photo library, add only | Optional. Saves an AR screenshot. | Only when the shutter is tapped |

No tracking, no analytics SDK, no advertising identifier.
`PrivacyInfo.xcprivacy` is included in both targets and matches the App Store
Connect answers.

## Not in this build

- **In-app purchases:** none. The app never links to external purchase.
- **Account creation:** not offered in-app; accounts come from the developer
  portal. The app is fully usable without one, so Guideline 5.1.1 sign-in gating
  does not apply.
- **3D model sandbox:** planned, not in this build.

## Devices tested

| Device | iOS | Result |
|---|---|---|
| _fill in_ | _fill in_ | _fill in_ |

Minimum supported: iOS 16.0. ARKit is required for the AR features; the app
explains this rather than crashing on a device without it.

## Contact during review

contact@multiset.ai — MultiSet AI, 28 Geary Street STE 650 Suite #371,
San Francisco, California 94108, USA.
