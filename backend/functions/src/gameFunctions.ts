import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { ageTierFor, computeDifficultyMix, pointsFor } from "./difficulty";
import { generateUniqueGameCode } from "./gameCode";
import { fetchGameQuestions } from "./opentdb";
import {
  COMPLETED_GAME_GRACE_MINUTES,
  GameDoc,
  QUESTIONS_PER_GAME,
  REST_STOP_TTL_HOURS,
  WAITING_GAME_TTL_HOURS,
} from "./types";

// playerId is always the caller's Firebase Anonymous Auth uid — never a
// client-supplied value — so a device can only ever read/write its own
// player entry. This is what Firestore security rules key off of too.

function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function gameRef(gameCode: string) {
  return db().collection("games").doc(gameCode) as FirebaseFirestore.DocumentReference<GameDoc>;
}

function requireAuth(auth: { uid: string } | undefined): string {
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign-in (anonymous) is required.");
  }
  return auth.uid;
}

function hoursFromNow(hours: number): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromMillis(Date.now() + hours * 60 * 60 * 1000);
}

function minutesFromNow(minutes: number): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromMillis(Date.now() + minutes * 60 * 1000);
}

function validAge(age: unknown): number {
  if (typeof age !== "number" || !Number.isInteger(age) || age < 1 || age > 119) {
    throw new HttpsError("invalid-argument", "age must be an integer between 1 and 119.");
  }
  return age;
}

function validDisplayName(name: unknown): string {
  if (typeof name !== "string" || name.trim().length === 0 || name.length > 24) {
    throw new HttpsError("invalid-argument", "displayName must be 1-24 characters.");
  }
  return name.trim();
}

export const createGame = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  const displayName = validDisplayName(request.data?.hostDisplayName);
  const age = validAge(request.data?.age);

  const gameCode = await generateUniqueGameCode(db());
  const now = admin.firestore.FieldValue.serverTimestamp();

  const game: Omit<GameDoc, "createdAt" | "updatedAt" | "expiresAt"> & {
    createdAt: admin.firestore.FieldValue;
    updatedAt: admin.firestore.FieldValue;
    expiresAt: admin.firestore.Timestamp;
  } = {
    status: "waiting",
    createdAt: now,
    updatedAt: now,
    pausedAt: null,
    currentQuestionIndex: -1,
    questionStartedAt: null,
    hostDeviceId: uid,
    driverPlayerId: uid,
    questions: [],
    players: {
      [uid]: {
        displayName,
        age,
        ageTier: ageTierFor(age),
        isDriver: true,
        score: 0,
        answers: {},
      },
    },
    expiresAt: hoursFromNow(WAITING_GAME_TTL_HOURS),
  };

  await gameRef(gameCode).set(game as unknown as GameDoc);
  return { gameCode, playerId: uid };
});

export const joinGame = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  const gameCode = String(request.data?.gameCode ?? "").toUpperCase();
  const displayName = validDisplayName(request.data?.displayName);
  const age = validAge(request.data?.age);

  const ref = gameRef(gameCode);

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", `No game with code ${gameCode}.`);
    }
    const game = snap.data() as GameDoc;

    // Idempotent: the same device (uid) reconnecting to a game it already
    // joined just returns successfully rather than erroring or resetting score.
    if (game.players[uid]) return;

    if (game.status !== "waiting") {
      throw new HttpsError("failed-precondition", "This game has already started.");
    }
    tx.update(ref, {
      [`players.${uid}`]: {
        displayName,
        age,
        ageTier: ageTierFor(age),
        isDriver: false,
        score: 0,
        answers: {},
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { playerId: uid };
});

/**
 * Self-service: a device declares itself the driver (e.g. when its
 * CarPlay scene connects). Any existing player in the game may call this
 * for themselves — it cannot be used to reassign another player.
 */
export const setDriver = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  const gameCode = String(request.data?.gameCode ?? "").toUpperCase();
  const ref = gameRef(gameCode);

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", `No game with code ${gameCode}.`);
    const game = snap.data() as GameDoc;
    if (!game.players[uid]) {
      throw new HttpsError("failed-precondition", "You must join the game before becoming the driver.");
    }
    const updates: Record<string, unknown> = {
      driverPlayerId: uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    for (const pid of Object.keys(game.players)) {
      updates[`players.${pid}.isDriver`] = pid === uid;
    }
    tx.update(ref, updates);
  });

  return { ok: true };
});

export const startGame = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  const gameCode = String(request.data?.gameCode ?? "").toUpperCase();
  const ref = gameRef(gameCode);

  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", `No game with code ${gameCode}.`);
  const game = snap.data() as GameDoc;
  if (game.hostDeviceId !== uid) {
    throw new HttpsError("permission-denied", "Only the host can start the game.");
  }
  if (game.status !== "waiting") {
    throw new HttpsError("failed-precondition", "This game has already started.");
  }
  const players = Object.values(game.players);
  if (players.length === 0) {
    throw new HttpsError("failed-precondition", "At least one player is required to start.");
  }

  const mix = computeDifficultyMix(players, QUESTIONS_PER_GAME);
  const questions = await fetchGameQuestions(db(), mix);

  await ref.update({
    questions,
    status: "active",
    currentQuestionIndex: 0,
    questionStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: hoursFromNow(REST_STOP_TTL_HOURS),
  });

  return { questionCount: questions.length, mix };
});

export const submitAnswer = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  const gameCode = String(request.data?.gameCode ?? "").toUpperCase();
  const questionIndex = Number(request.data?.questionIndex);
  const choice = request.data?.choice === null ? null : String(request.data?.choice ?? "");

  const ref = gameRef(gameCode);

  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", `No game with code ${gameCode}.`);
    const game = snap.data() as GameDoc;

    if (game.status !== "active") {
      throw new HttpsError("failed-precondition", "Game is not active.");
    }
    if (questionIndex !== game.currentQuestionIndex) {
      throw new HttpsError("failed-precondition", "That question is no longer active.");
    }
    const player = game.players[uid];
    if (!player) throw new HttpsError("failed-precondition", "You are not in this game.");
    if (player.answers[String(questionIndex)]) {
      throw new HttpsError("already-exists", "You already answered this question.");
    }

    const question = game.questions[questionIndex];
    const correct = choice !== null && choice === question.correctAnswer;
    const pointsEarned = correct ? pointsFor(player.ageTier, question.difficulty) : 0;

    tx.update(ref, {
      [`players.${uid}.answers.${questionIndex}`]: {
        choice,
        correct,
        pointsEarned,
        answeredAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      [`players.${uid}.score`]: admin.firestore.FieldValue.increment(pointsEarned),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { correct, pointsEarned };
  });

  return result;
});

export const advanceQuestion = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  const gameCode = String(request.data?.gameCode ?? "").toUpperCase();
  const ref = gameRef(gameCode);

  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", `No game with code ${gameCode}.`);
    const game = snap.data() as GameDoc;
    if (game.hostDeviceId !== uid) {
      throw new HttpsError("permission-denied", "Only the host can advance the game.");
    }
    if (game.status !== "active") {
      throw new HttpsError("failed-precondition", "Game is not active.");
    }

    const nextIndex = game.currentQuestionIndex + 1;
    const isComplete = nextIndex >= game.questions.length;

    tx.update(ref, {
      currentQuestionIndex: isComplete ? game.currentQuestionIndex : nextIndex,
      questionStartedAt: isComplete ? null : admin.firestore.FieldValue.serverTimestamp(),
      status: isComplete ? "completed" : "active",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: isComplete ? minutesFromNow(COMPLETED_GAME_GRACE_MINUTES) : hoursFromNow(REST_STOP_TTL_HOURS),
    });

    return { currentQuestionIndex: isComplete ? game.currentQuestionIndex : nextIndex, isComplete };
  });

  return result;
});

export const pauseGame = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  const gameCode = String(request.data?.gameCode ?? "").toUpperCase();
  const ref = gameRef(gameCode);

  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", `No game with code ${gameCode}.`);
  const game = snap.data() as GameDoc;
  if (!game.players[uid]) {
    throw new HttpsError("failed-precondition", "You are not in this game.");
  }

  await ref.update({
    status: "paused",
    pausedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: hoursFromNow(REST_STOP_TTL_HOURS),
  });

  return { ok: true };
});

export const resumeGame = onCall(async (request) => {
  const uid = requireAuth(request.auth);
  const gameCode = String(request.data?.gameCode ?? "").toUpperCase();
  const ref = gameRef(gameCode);

  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", `No game with code ${gameCode}.`);
  const game = snap.data() as GameDoc;
  if (!game.players[uid]) {
    throw new HttpsError("failed-precondition", "You are not in this game.");
  }
  if (game.status !== "paused") {
    throw new HttpsError("failed-precondition", "Game is not paused.");
  }

  await ref.update({
    status: "active",
    pausedAt: null,
    questionStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: hoursFromNow(REST_STOP_TTL_HOURS),
  });

  return { currentQuestionIndex: game.currentQuestionIndex };
});

/**
 * Backup sweep for stale "waiting" games (host abandoned lobby) and any
 * doc Firestore's native TTL hasn't yet reaped. Firestore TTL deletion can
 * lag up to ~24h, so this catches abandoned lobbies faster.
 */
export const cleanupStaleGames = onSchedule("every 30 minutes", async () => {
  const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - WAITING_GAME_TTL_HOURS * 60 * 60 * 1000);
  const staleWaiting = await db()
    .collection("games")
    .where("status", "==", "waiting")
    .where("createdAt", "<", cutoff)
    .get();

  const expired = await db().collection("games").where("expiresAt", "<", admin.firestore.Timestamp.now()).get();

  const batch = db().batch();
  staleWaiting.docs.forEach((d) => batch.delete(d.ref));
  expired.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
});
