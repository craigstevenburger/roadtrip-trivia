# Road Trip Trivia — Backend API Contract

This is the source of truth for the Firestore schema and Cloud Functions
contract. Any client (the iOS app now, an Android client later) must talk to
the backend only through this contract — no client should ever call OpenTDB
directly or compute scores/difficulty locally, so behavior stays identical
across platforms.

## Firestore Schema

### `games/{gameCode}`

`gameCode` is a 6-character uppercase alphanumeric code (excludes `0/O/1/I`
to avoid spoken/visual ambiguity), generated server-side.

```ts
{
  status: "waiting" | "active" | "paused" | "completed",
  createdAt: Timestamp,
  updatedAt: Timestamp,
  pausedAt: Timestamp | null,
  currentQuestionIndex: number,        // 0-based, -1 before game start
  questionStartedAt: Timestamp | null, // set when a question is revealed, drives the 20s window
  hostDeviceId: string,
  driverPlayerId: string | null,       // which player is the driver (voice-only)
  questions: [
    {
      id: string,                      // opentdb question hash
      category: string,
      difficulty: "easy" | "medium" | "hard",
      question: string,                // HTML-entity-decoded
      correctAnswer: string,
      options: string[],                // decoded, shuffled once server-side, same order for all clients
    }
  ],
  players: {
    [playerId: string]: {
      displayName: string,             // local nickname, not an account
      age: number,
      ageTier: "child" | "teen" | "adult",   // child <14, teen 14-18, adult 19+
      isDriver: boolean,
      score: number,
      answers: {
        [questionIndex: string]: {
          choice: string | null,       // null = no answer / timed out
          correct: boolean,
          pointsEarned: number,
          answeredAt: Timestamp,
        }
      }
    }
  },
  expiresAt: Timestamp,                // Firestore TTL field; doc auto-deletes
}
```

Firestore's native TTL policy is configured on `expiresAt` for automatic
cleanup — no cron job needed for the common case. `expiresAt` is refreshed on
every pause/resume so an active-but-idle game doesn't expire mid-trip.

## Cloud Functions (callable, region `us-central1`)

All functions are HTTPS Callable Functions, invoked with Firebase Anonymous
Auth (no email/password, no real accounts). **`playerId` is always the
caller's `context.auth.uid`** — never a client-supplied value — so a device
can only ever read/write its own player entry, and Firestore security rules
key directly off `request.auth.uid`.

### `createGame({ hostDisplayName, age })`
Generates a unique `gameCode`, creates the `games/{gameCode}` doc with
`status: "waiting"`, adds the caller (by uid) as the first player, host,
and default driver. Returns `{ gameCode, playerId }` where `playerId == uid`.

### `joinGame({ gameCode, displayName, age })`
Validates the game exists and `status == "waiting"`, adds the caller (by
uid) to `players`. Idempotent — a device rejoining a game it's already in
just returns successfully rather than resetting its score. Returns
`{ playerId }`. Errors: `not-found`, `failed-precondition` (game already
started).

### `setDriver({ gameCode })`
Self-service: the calling device declares itself the driver (fired when its
CarPlay scene connects). A device can only ever mark *itself* as driver —
this is what lets the backend know whose spoken answer to listen for once
the CarPlay client wires up in Phase 3.

### `startGame({ gameCode })`
Host-only (`hostDeviceId == uid`), requires `status == "waiting"` and ≥1 player.
1. Computes average player age and the under-10 flag from `players`.
2. Applies the difficulty-mix table (see below) to produce an easy/medium/
   hard split summing to 20.
3. Fetches questions from OpenTDB (session-token-authenticated, one batch
   per difficulty), decodes HTML entities, shuffles each question's options
   with a per-question fixed seed persisted in the doc.
4. Writes the 20 `questions`, sets `status: "active"`, `currentQuestionIndex: 0`,
   `questionStartedAt: now`.

### `submitAnswer({ gameCode, questionIndex, choice })`
Records the caller's answer if `questionIndex == currentQuestionIndex` and
they haven't already answered. Computes `correct` + `pointsEarned` from the
scoring table (see below) and writes it under
`players.{uid}.answers.{questionIndex}`, incrementing `score`.

### `advanceQuestion({ gameCode })`
Host-only. Called once the 20s window elapses or all non-driver players
(plus the driver's spoken answer) have answered. Increments
`currentQuestionIndex`, resets `questionStartedAt`; if the new index is 20,
sets `status: "completed"` and `expiresAt` to 5 minutes out (short grace
period, then TTL cleanup removes the doc).

### `pauseGame({ gameCode })` / `resumeGame({ gameCode })`
Callable by any participant. Sets `status: "paused"` / `"active"` and bumps
`expiresAt` by the rest-stop TTL window (4 hours) on every pause, so a long
stop doesn't lose the game.

## Difficulty-Mix Table (used by `startGame`)

Keyed by average player age at game start; largest-remainder rounding is
used so the three counts always sum to exactly 20.

| Avg age | Easy | Medium | Hard |
|---|---|---|---|
| 10–13 | 60% | 35% | 5% |
| 14–17 | 40% | 40% | 20% |
| 18–35 | 25% | 40% | 35% |
| 36–55 | 20% | 35% | 45% |
| 56+ | 15% | 30% | 55% |

**Override:** if any player's `age < 10`, hard is forced to 0% and that
share folds into medium, regardless of the computed average-age band.

## Scoring Table (used by `submitAnswer`)

| Age tier | Easy | Medium | Hard |
|---|---|---|---|
| Child (<14) | 3 | 4 | 5 |
| Teen (14–18) | 2 | 3 | 4 |
| Adult (19+) | 1 | 2 | 3 |

## OpenTDB Usage Notes

- Base URL: `https://opentdb.com`
- Session token: `GET /api_token.php?command=request` once, cached in
  Cloud Functions config/Firestore; reset via `command=reset` when the API
  returns response code `4` (all questions for that token exhausted).
- Questions: `GET /api.php?amount={n}&difficulty={easy|medium|hard}&type=multiple&token={token}`
- Response `response_code`: `0` success, `1` not enough questions for the
  filter (fall back to a smaller amount or drop the difficulty filter),
  `3`/`4` token invalid/exhausted (request a new token and retry once).
- All OpenTDB calls happen **only** inside `startGame` — never from a
  client — both to respect OpenTDB's rate limit (~1 req/5s per IP) and to
  guarantee every player in a game sees identical questions.
