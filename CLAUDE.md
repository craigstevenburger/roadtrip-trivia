# CLAUDE.md

Operational notes for agent sessions. See [`README.md`](README.md) for repo
layout, setup instructions, and phase status — don't duplicate that here.

## iOS

- `ios/RoadTripTrivia.xcodeproj` is gitignored and generated from
  `ios/project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  Run `cd ios && xcodegen generate` after any `project.yml` change, and
  before the first build in a fresh checkout.
- `ios/RoadTripTrivia/Info.plist` is committed and must be kept in sync by
  hand with `project.yml`'s `targets.RoadTripTrivia.info.properties` (e.g.
  usage description strings) — `xcodegen generate` will overwrite it from
  `project.yml`, so treat `project.yml` as the source of truth and mirror
  new keys into the checked-in Info.plist in the same edit.
- The `xcodebuildmcp` MCP server is configured (see `.mcp.json`) — prefer
  its tools over raw `xcodebuild`/`xcrun simctl` shell commands for
  building, running, and screenshotting the simulator.

## Backend

- The `firebase` MCP server is configured (see `.mcp.json`), scoped to
  `backend/` (project `roadtriptrivia-d3451`) — prefer it over the raw
  `firebase` CLI for Firestore/Functions/project inspection.
- `docs/api-contract.md` is the source of truth for the Firestore schema
  and Cloud Functions contract; keep client and backend changes consistent
  with it rather than inferring behavior from one side alone.
