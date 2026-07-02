import * as admin from "firebase-admin";
import { Difficulty, QuestionDoc } from "./types";

const BASE_URL = "https://opentdb.com";
const TOKEN_DOC_PATH = "config/opentdb";

// url3986-encoded responses avoid HTML-entity decoding entirely — every
// field just needs decodeURIComponent().
const QUESTION_TYPE = "multiple";

interface OpenTdbApiQuestion {
  category: string;
  type: string;
  difficulty: Difficulty;
  question: string;
  correct_answer: string;
  incorrect_answers: string[];
}

interface OpenTdbApiResponse {
  response_code: number;
  results: OpenTdbApiQuestion[];
}

async function getStoredToken(db: FirebaseFirestore.Firestore): Promise<string | null> {
  const snap = await db.doc(TOKEN_DOC_PATH).get();
  return snap.exists ? (snap.data()?.token ?? null) : null;
}

async function storeToken(db: FirebaseFirestore.Firestore, token: string): Promise<void> {
  await db.doc(TOKEN_DOC_PATH).set({ token, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
}

async function requestNewToken(db: FirebaseFirestore.Firestore): Promise<string> {
  const res = await fetch(`${BASE_URL}/api_token.php?command=request`);
  const body = (await res.json()) as { response_code: number; token: string };
  if (body.response_code !== 0) {
    throw new Error(`Failed to obtain OpenTDB session token (code ${body.response_code}).`);
  }
  await storeToken(db, body.token);
  return body.token;
}

async function resetToken(db: FirebaseFirestore.Firestore, token: string): Promise<string> {
  const res = await fetch(`${BASE_URL}/api_token.php?command=reset&token=${token}`);
  const body = (await res.json()) as { response_code: number; token: string };
  if (body.response_code !== 0) {
    return requestNewToken(db);
  }
  await storeToken(db, body.token);
  return body.token;
}

async function getOrCreateToken(db: FirebaseFirestore.Firestore): Promise<string> {
  const existing = await getStoredToken(db);
  return existing ?? requestNewToken(db);
}

function decode(s: string): string {
  return decodeURIComponent(s);
}

function shuffle<T>(items: T[]): T[] {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function toQuestionDoc(raw: OpenTdbApiQuestion): QuestionDoc {
  const question = decode(raw.question);
  const correctAnswer = decode(raw.correct_answer);
  const options = shuffle([correctAnswer, ...raw.incorrect_answers.map(decode)]);
  return {
    // OpenTDB has no stable question id, so derive a stable-enough one from content.
    id: Buffer.from(`${question}:${correctAnswer}`).toString("base64").slice(0, 24),
    category: decode(raw.category),
    difficulty: raw.difficulty,
    question,
    correctAnswer,
    options,
  };
}

async function fetchBatch(
  db: FirebaseFirestore.Firestore,
  difficulty: Difficulty,
  amount: number,
  attempt = 0
): Promise<QuestionDoc[]> {
  if (amount <= 0) return [];

  const token = await getOrCreateToken(db);
  const url = `${BASE_URL}/api.php?amount=${amount}&difficulty=${difficulty}&type=${QUESTION_TYPE}&encode=url3986&token=${token}`;
  const res = await fetch(url);
  const body = (await res.json()) as OpenTdbApiResponse;

  switch (body.response_code) {
    case 0:
      return body.results.map(toQuestionDoc);
    case 3: // token not found
    case 4: // token exhausted for this filter combo
      if (attempt >= 1) {
        throw new Error(`OpenTDB token retry failed for ${difficulty} x${amount}.`);
      }
      await resetToken(db, token);
      return fetchBatch(db, difficulty, amount, attempt + 1);
    case 1: // not enough questions available for this filter
      if (amount <= 1) return [];
      // Ask for fewer; caller's apportionment absorbs the shortfall.
      return fetchBatch(db, difficulty, amount - 1, attempt);
    default:
      throw new Error(`Unexpected OpenTDB response_code ${body.response_code} for ${difficulty} x${amount}.`);
  }
}

/**
 * Fetches and decodes the full question set for a game given the
 * difficulty mix computed by computeDifficultyMix(). Runs entirely
 * server-side — clients never call OpenTDB directly.
 */
export async function fetchGameQuestions(
  db: FirebaseFirestore.Firestore,
  mix: Record<Difficulty, number>
): Promise<QuestionDoc[]> {
  const [easy, medium, hard] = await Promise.all([
    fetchBatch(db, "easy", mix.easy),
    fetchBatch(db, "medium", mix.medium),
    fetchBatch(db, "hard", mix.hard),
  ]);
  return shuffle([...easy, ...medium, ...hard]);
}
