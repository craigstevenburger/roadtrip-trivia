// Excludes 0/O and 1/I so a spoken or glanced-at code isn't ambiguous.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 6;
const MAX_ATTEMPTS = 10;

function randomCode(): string {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return code;
}

/** Generates a game code guaranteed not to collide with an in-progress game. */
export async function generateUniqueGameCode(
  db: FirebaseFirestore.Firestore
): Promise<string> {
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const code = randomCode();
    const existing = await db.collection("games").doc(code).get();
    if (!existing.exists) {
      return code;
    }
  }
  throw new Error("Could not generate a unique game code, please retry.");
}
