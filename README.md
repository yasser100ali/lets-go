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

## Backend

`backend/` is a FastAPI + Postgres API for the shared version: device accounts with bearer tokens, `/v1/nearby` (gatherings and kitchens around a point), hosting, joining and **server-checked check-ins** (within 200 m, from 30 min before start), kitchens with menus and drops, and **orders that can't oversell** (the drop row is locked while stock and the 15-minute slot are checked; a retried request with the same `client_id` returns the same order). Pickup notes only go to the cook and to people with an order. Reviews only after pickup, one per order.

```bash
docker compose up                                   # api on :8100, Postgres on :5433
docker compose run --rm --no-deps api pytest -q     # 20 tests
```

Schema changes go through Alembic (`alembic revision --autogenerate`, then read it). CI runs lint, `alembic check` and the tests.

The app talks to it when it has a server address: under **You → Server** (an ngrok URL to your Mac works), `LETSGO_API` in the Xcode scheme, or `APIConfig.deployed` once there's a real deployment. With no address it runs on the phone's own data, as before. Things from the server are pulled into the on-phone store on launch, on returning to the app and when you move; joining, check-ins, hosting, kitchens, drops, orders and reviews go to the server first when the thing lives there.

iOS integration tests against a running backend:

```bash
TEST_RUNNER_LETSGO_API=http://localhost:8100 xcodebuild test -project ios/LetsGo.xcodeproj -scheme LetsGo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Deployed on Railway: project **lets-go**, services `api` (this Dockerfile; runs `alembic upgrade head` on start) and `Postgres`, at https://api-production-658b9.up.railway.app. Deploy from `backend/` with `railway up --service api`. The app uses it by default (`APIConfig.deployed`); You → Server overrides it.

## Not yet

- Payments — you pay the cook at pickup.
- Sign in with Apple, push notifications, Live Activities.

## Layout

```
ios/
  project.yml          XcodeGen spec — the source of truth for the project
  LetsGo.xcodeproj     generated; commit it, but change project.yml, then `xcodegen generate`
  Config.xcconfig      bundle id, team, version, build number
  LetsGo/              app sources (synced folder: new files are picked up automatically)
  LetsGoTests/         Swift Testing
backend/               FastAPI + SQLAlchemy async + Alembic
docker-compose.yml     local api (:8100) + Postgres (:5433)
scripts/
  ship.sh              archive → sign → upload to TestFlight (build number from App Store Connect)
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

Ship a TestFlight build from GitHub: **Actions → "iOS CD — TestFlight" → Run workflow** (or `gh workflow run ios-cd.yml -R yasser100ali/lets-go`). It runs the tests, then archives, signs and uploads on the Mac mini's Let's Go runner (`~/actions-runner-letsgo`, label `letsgo`, next to Pulse's), and waits for Apple to finish processing. Internal testers get it automatically.

From this Mac directly:

```bash
scripts/ship.sh
```

Both need, outside the repo: the App Store Connect key at `~/.appstoreconnect/letsgo_asc_api_key.json` (+ `private_keys/AuthKey_*.p8`), and the signing bundle in `~/.appstoreconnect/letsgo-signing/` (Let's Go's own Apple Distribution cert, its keychain password and the App Store profile). On a new Mac run `scripts/setup-signing.sh` once.
