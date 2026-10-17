# Let's Go

Pokémon Go for hanging out. A live night map of what's happening within walking distance — pickup games, runs, backyard sets, game nights — and neighbors selling what they're good at cooking, out of their own houses. Wren, the AI, learns what you actually show up for and tells you what's worth leaving the house for.

Working name. The mocks this was built from: https://claude.ai/artifact/WxbnSewLmj7KwW69GwS1ys (direction A's map with C's Wren line).

## What's in v0.1

- **Map** — glowing pins for everything on in the next three hours, pulsing while they fill up; a dashed ring for a 10-minute walk; Wren's one line and top three picks on the panel.
- **Gatherings** — headcount, what to bring, who runs it. Join, and check in when you're physically within 200 m to collect a stamp. Host your own from the + button or by telling Wren.
- **Kitchens** — a page per home kitchen with its drop (a fixed batch at a set time), menu and reviews. Reserve a pickup slot or a porch seat; the pickup spot unlocks after you reserve. Mark it picked up, leave a review; three visits makes you a regular.
- **Your kitchen** — open one, keep a menu, post drops, see what sold. Permit checklist (MEHKO in California).
- **Wren** — ask for a mood ("something chill tonight under $15") and get real nearby options; describe a plan ("slow jog sat 8am around the lake") and get a draft to post. Uses Apple's on-device model when the phone has Apple Intelligence, a local parser otherwise.
- **Passport** — stamps, counts, and everything Wren believes about you, deletable.

Everything is on-device (SwiftData) for now. Until real neighbors post, a **sample neighborhood** is placed around you, every item tagged *Sample*; turn it off under You.

## Not yet

- A backend, so what you post reaches other people. (Next.)
- Payments — you pay the cook at pickup.
- Accounts, push notifications, Live Activities.

## Layout

```
ios/
  project.yml          XcodeGen spec — the source of truth for the project
  LetsGo.xcodeproj     generated; commit it, but change project.yml, then `xcodegen generate`
  Config.xcconfig      bundle id, team, version, build number
  LetsGo/              app sources (synced folder: new files are picked up automatically)
  LetsGoTests/         Swift Testing
scripts/
  ship.sh              bump build → archive → upload to TestFlight
  asc.py               App Store Connect API: app record, testers, build status
  setup-signing.sh     rebuild the prompt-free signing keychain on a new Mac
```

## Run

```bash
cd ios && xcodegen generate   # only after editing project.yml
open ios/LetsGo.xcodeproj
```

Tests:

```bash
xcodebuild test -project ios/LetsGo.xcodeproj -scheme LetsGo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Ship a TestFlight build. Needs, outside the repo: the App Store Connect key at `~/.appstoreconnect/letsgo_asc_api_key.json` (+ `private_keys/AuthKey_*.p8`), and the signing bundle in `~/.appstoreconnect/letsgo-signing/` (Let's Go's own Apple Distribution cert, its keychain password and the App Store profile). On a new Mac run `scripts/setup-signing.sh` once.

```bash
scripts/ship.sh
```
