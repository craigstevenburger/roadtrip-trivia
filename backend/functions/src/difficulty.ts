import { AgeTier, Difficulty, PlayerDoc, QUESTIONS_PER_GAME } from "./types";

export function ageTierFor(age: number): AgeTier {
  if (age < 14) return "child";
  if (age <= 18) return "teen";
  return "adult";
}

// pointsFor[ageTier][difficulty]
const SCORING_TABLE: Record<AgeTier, Record<Difficulty, number>> = {
  child: { easy: 3, medium: 4, hard: 5 },
  teen: { easy: 2, medium: 3, hard: 4 },
  adult: { easy: 1, medium: 2, hard: 3 },
};

export function pointsFor(ageTier: AgeTier, difficulty: Difficulty): number {
  return SCORING_TABLE[ageTier][difficulty];
}

interface DifficultyMix {
  easy: number;
  medium: number;
  hard: number;
}

// Bands keyed by the upper bound of the average-age range they cover.
// [maxAvgAge, {easy, medium, hard} as fractions summing to 1]
const AGE_BANDS: Array<{ maxAvgAge: number; mix: DifficultyMix }> = [
  { maxAvgAge: 13, mix: { easy: 0.6, medium: 0.35, hard: 0.05 } },
  { maxAvgAge: 17, mix: { easy: 0.4, medium: 0.4, hard: 0.2 } },
  { maxAvgAge: 35, mix: { easy: 0.25, medium: 0.4, hard: 0.35 } },
  { maxAvgAge: 55, mix: { easy: 0.2, medium: 0.35, hard: 0.45 } },
  { maxAvgAge: Infinity, mix: { easy: 0.15, medium: 0.3, hard: 0.55 } },
];

function mixForAverageAge(avgAge: number): DifficultyMix {
  const band = AGE_BANDS.find((b) => avgAge <= b.maxAvgAge);
  return band ? band.mix : AGE_BANDS[AGE_BANDS.length - 1].mix;
}

/** Largest-remainder rounding so counts always sum to exactly `total`. */
function apportion(mix: DifficultyMix, total: number): Record<Difficulty, number> {
  const entries: Array<[Difficulty, number]> = [
    ["easy", mix.easy],
    ["medium", mix.medium],
    ["hard", mix.hard],
  ];
  const raw = entries.map(([key, frac]) => ({ key, exact: frac * total }));
  const floored = raw.map((r) => ({ key: r.key, count: Math.floor(r.exact), remainder: r.exact - Math.floor(r.exact) }));

  let assigned = floored.reduce((sum, r) => sum + r.count, 0);
  const remaining = total - assigned;

  floored
    .slice()
    .sort((a, b) => b.remainder - a.remainder)
    .slice(0, remaining)
    .forEach((r) => {
      const target = floored.find((f) => f.key === r.key)!;
      target.count += 1;
      assigned += 1;
    });

  const result = { easy: 0, medium: 0, hard: 0 } as Record<Difficulty, number>;
  floored.forEach((r) => (result[r.key] = r.count));
  return result;
}

/**
 * Computes the easy/medium/hard question counts for a game given the
 * players in the session. Any player under 10 forces hard to zero,
 * folding that share into medium — this overrides the average-age band.
 */
export function computeDifficultyMix(
  players: Pick<PlayerDoc, "age">[],
  total: number = QUESTIONS_PER_GAME
): Record<Difficulty, number> {
  if (players.length === 0) {
    throw new Error("Cannot compute a difficulty mix with no players.");
  }

  const avgAge = players.reduce((sum, p) => sum + p.age, 0) / players.length;
  const hasChildUnder10 = players.some((p) => p.age < 10);

  let mix = mixForAverageAge(avgAge);
  if (hasChildUnder10 && mix.hard > 0) {
    mix = { easy: mix.easy, medium: mix.medium + mix.hard, hard: 0 };
  }

  return apportion(mix, total);
}
