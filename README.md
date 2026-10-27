# Let's Go

Pokémon Go for hanging out. A live night map of what's happening within walking distance — pickup games, runs, backyard sets, game nights — and neighbors selling what they're good at cooking, out of their own houses. Wren, the AI, learns what you actually show up for and tells you what's worth leaving the house for.

Working name. The mocks this was built from: https://claude.ai/artifact/WxbnSewLmj7KwW69GwS1ys (direction A's map with C's Wren line).

## What's in it

**LIVE. MORE.** A social app boosted by AI: it's about getting out and being with people, not about time on the screen, and Wren does the logistics so you can go. It opens on the map, and the first launch opens on the line it's named for (Dostoevsky, *Demons*), clause by clause. Passport → *Read the quote again* brings it back. Designs: https://claude.ai/artifact/VrtFdCRFcZzKaV6f2vJ4AE.

- **Map (the opening screen)** — *Afterglow*: a night-tinted map with glowing pins for everything on in the next three hours. Pins pulse while they fill, faster the fuller they get, with a count on each ("4/6", "16 left"); a dashed ring marks a 10-minute walk. Wren's line sits on a glass sheet at the bottom: the one thing worth going to, why, when to leave, and *I'm in* right there; *Not tonight* moves on to the next. Filters: Now, Tonight, Weekend, kinds of thing, Free. Drag the sheet up (or tap search) for the whole list. Walk view still tilts the map into the street.
- **Quick pick** — the *Signal* look as a filter mode: black and lime, the top three numbered on the map with real walking routes, *leave by* times, and a ruler of the next five hours you can drag to look ahead.
- **Plans** — what you've said yes to (gatherings, pickups), then what used to be Today: the one pick, what starts in the next hour, what's within a 15-minute walk, the week's real listings day by day (weeks start Monday), places from the city list, and kitchens with a drop coming. Sunset time is worked out on the phone (`Sun`).
- **Passport** — show-ups, kitchens tried, *Know your city: SF 50* (fifty places every San Franciscan should go once, `sf_places.json`, closest first, with progress by kind; each place has a page, and checking in within 200 m stamps it), stamps, and everything Wren believes about you, deletable. Settings live at the bottom.
- **Wren** — the round button at the end of the tab bar. Ask for a mood ("something chill tonight under $15") and get real nearby options; describe a plan ("host a slow jog sat 8am around the lake") and get a draft to post.
- **Gatherings** — headcount, what to bring, who runs it. Join, and check in when you're physically within 200 m to collect a stamp. Host your own from the + button or by telling Wren.
- **Kitchens** — a page per home kitchen with its drop (a fixed batch at a set time), menu and reviews. Reserve a pickup slot or a porch seat; the pickup spot unlocks after you reserve. Mark it picked up, leave a review; three visits makes you a regular.
- **Your kitchen** — open one, keep a menu, post drops, see what sold. Permit checklist (MEHKO in California).

Everything is on-device (SwiftData) for now. Until real neighbors post, a **sample neighborhood** is placed around you, every item tagged *Sample*; turn it off at the bottom of Passport.

## Backend

`backend/` is a FastAPI + Postgres API for the shared version: device accounts with bearer tokens, `/v1/nearby` (gatherings and kitchens around a point), hosting, joining and **server-checked check-ins** (within 200 m, from 30 min before start), kitchens with menus and drops, and **orders that can't oversell** (the drop row is locked while stock and the 15-minute slot are checked; a retried request with the same `client_id` returns the same order). Pickup notes only go to the cook and to people with an order. Reviews only after pickup, one per order.

```bash
docker compose up                                   # api on :8100, Postgres on :5433
docker compose run --rm --no-deps api pytest -q
```

**Listings** (`/v1/listings?city=sf`, no account needed) are the real city: shows, markets, weekly regulars, in the same shape as the app's `sf_happenings.json`. The phone fetches them on launch and when it comes back, keeps the last copy for offline, and falls back to the bundled file before its first fetch. Load or refresh them with:

```bash
cd backend && python -m app.listings_import ../ios/LetsGo/Resources/sf_happenings.json              # local
DATABASE_URL=<Railway Postgres public URL> python -m app.listings_import ../ios/LetsGo/Resources/sf_happenings.json  # deployed
```

Rows match on city, title and venue; ones the file no longer has are marked gone. Until the import runs, the phone also shows bundled listings the server doesn't have yet (same title and venue counts as the same listing). This is where the nightly scout will write.

Schema changes go through Alembic (`alembic revision --autogenerate`, then read it). CI runs lint, `alembic check` and the tests.

The app talks to it when it has a server address: under **Passport → Server** (an ngrok URL to your Mac works), `LETSGO_API` in the Xcode scheme, or `APIConfig.deployed` once there's a real deployment. With no address it runs on the phone's own data, as before. Things from the server are pulled into the on-phone store on launch, on returning to the app and when you move; joining, check-ins, hosting, kitchens, drops, orders and reviews go to the server first when the thing lives there.

iOS integration tests against a running backend:

```bash
TEST_RUNNER_LETSGO_API=http://localhost:8100 xcodebuild test -project ios/LetsGo.xcodeproj -scheme LetsGo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Deployed on Railway: project **lets-go**, services `api` (this Dockerfile; runs `alembic upgrade head` on start) and `Postgres`, at https://api-production-658b9.up.railway.app. Deploy from `backend/` with `railway up --service api`. The app uses it by default (`APIConfig.deployed`); Passport → Server overrides it.

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
