# Road Trip Trivia

Multiplayer trivia for the car — driver plays hands-free through Apple
CarPlay by voice, passengers play by tapping on their own phones. Questions
come from [OpenTDB](https://opentdb.com), difficulty and scoring scale with
the players' ages, and games can pause for a rest stop and pick back up
later. See [`docs/api-contract.md`](docs/api-contract.md) for the full
backend contract and the plan this was built from for architecture context.

**Status:** Phases 0–2 are implemented — Firebase backend, iPhone age gate /
create / join / lobby, and a phone-only (tap-to-answer) gameplay loop end to
end. Phase 4's rest-stop auto-detection is also in: with location
permission granted, the app notices via CoreLocation when the car has been
stopped or moving for a sustained stretch and offers to pause/resume,
alongside the existing manual pause/resume. CarPlay's voice-only driver
experience (Phase 3), ads, and branding assets are next — see "What's not
built yet" below.

## Repo layout

```
backend/            Firebase project — Cloud Functions (TypeScript) + Firestore rules
  functions/src/     Game logic: game codes, OpenTDB fetch, difficulty/scoring, pause/resume
docs/
  api-contract.md    Firestore schema + Cloud Function contract (read this first)
ios/                 SwiftUI iPhone app (XcodeGen project — see below)
  project.yml         XcodeGen spec; generates the .xcodeproj (not committed)
  RoadTripTrivia/      App source
assets/              Logo/branding source files (not yet populated)
```

## Backend setup

Requires a Firebase project (Blaze plan — Cloud Functions need outbound
network access to call OpenTDB) and the Firebase CLI.

```bash
npm install -g firebase-tools   # if you don't have it
cd backend
firebase login
# Replace the placeholder project id, or run: firebase use --add
$EDITOR .firebaserc
cd functions && npm install && cd ..
firebase deploy --only functions,firestore:rules,firestore:indexes
```

Then, one-time, enable native Firestore TTL deletion on `expiresAt`
(cleans up completed/expired games automatically — `cleanupStaleGames` is a
30-minute backup sweep, not the primary mechanism):

```bash
gcloud firestore fields ttls update expiresAt --collection-group=games --enable-ttl
```

Also enable **Anonymous** sign-in under Firebase Console → Authentication →
Sign-in method — the app never asks for an account, but uses an anonymous
uid as the stable per-device player id (see `docs/api-contract.md`).

For local iteration without touching production OpenTDB quota:

```bash
cd backend/functions && npm run serve   # Firestore + Functions emulators
```

## iOS app setup

This environment doesn't have full Xcode installed (only Command Line
Tools), so the project is authored as an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
spec rather than a committed `.xcodeproj` — regenerate it locally:

```bash
brew install xcodegen
cd ios
xcodegen generate
open RoadTripTrivia.xcodeproj
```

Before building:
1. In the Firebase console, add an iOS app to your project (bundle id
   `com.roadtriptrivia.app`, matching `project.yml`), download
   `GoogleService-Info.plist`, and drop it in
   `ios/RoadTripTrivia/Resources/`.
2. Xcode will resolve the Firebase iOS SDK via Swift Package Manager on
   first open (may take a few minutes).

To test multiplayer locally, run the app on two Simulator instances (or a
Simulator + a physical device) — one starts a game, the other joins with
the generated code.

## What's not built yet

Following the phased plan in order:

- **Phase 3 — CarPlay.** `CPNowPlayingTemplate` scene, `AVSpeechSynthesizer`
  question narration, `SFSpeechRecognizer` capture of the driver's spoken
  answer, plus the Mic/Speech Info.plist usage strings those need (held
  off on adding those until there's actual code behind them). Deliberately
  not started yet — flagged for a check-in before building, since it's the
  highest-uncertainty piece (Apple's CarPlay Audio App entitlement
  approval).
- **Phase 5 — Ads (AdMob banners, phone screens only).**
- **Phase 6 — Logo + splash screen audio sequencing.**
- **Phase 7 — Apple CarPlay entitlement request + App Store submission.**
- **Phase 8 — Android / Android Auto client**, built against the same
  Firebase backend and `docs/api-contract.md`.
