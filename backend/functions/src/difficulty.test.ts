import { ageTierFor, computeDifficultyMix, pointsFor } from "./difficulty";
import { AgeTier, Difficulty, QUESTIONS_PER_GAME } from "./types";

describe("ageTierFor", () => {
  it("classifies child, teen, and adult boundaries", () => {
    expect(ageTierFor(1)).toBe("child");
    expect(ageTierFor(13)).toBe("child");
    expect(ageTierFor(14)).toBe("teen");
    expect(ageTierFor(18)).toBe("teen");
    expect(ageTierFor(19)).toBe("adult");
    expect(ageTierFor(80)).toBe("adult");
  });
});

describe("pointsFor", () => {
  const expected: Record<AgeTier, Record<Difficulty, number>> = {
    child: { easy: 3, medium: 4, hard: 5 },
    teen: { easy: 2, medium: 3, hard: 4 },
    adult: { easy: 1, medium: 2, hard: 3 },
  };

  for (const ageTier of Object.keys(expected) as AgeTier[]) {
    for (const difficulty of Object.keys(expected[ageTier]) as Difficulty[]) {
      it(`awards ${expected[ageTier][difficulty]} points for ${ageTier}/${difficulty}`, () => {
        expect(pointsFor(ageTier, difficulty)).toBe(expected[ageTier][difficulty]);
      });
    }
  }
});

describe("computeDifficultyMix", () => {
  it("throws with no players", () => {
    expect(() => computeDifficultyMix([], QUESTIONS_PER_GAME)).toThrow();
  });

  it("defaults total to QUESTIONS_PER_GAME", () => {
    const mix = computeDifficultyMix([{ age: 25 }]);
    expect(mix.easy + mix.medium + mix.hard).toBe(QUESTIONS_PER_GAME);
  });

  it.each([
    // [avgAge, expected mix at total=20]
    [10, { easy: 12, medium: 7, hard: 1 }],
    [15, { easy: 8, medium: 8, hard: 4 }],
    [25, { easy: 5, medium: 8, hard: 7 }],
    [45, { easy: 4, medium: 7, hard: 9 }],
    [60, { easy: 3, medium: 6, hard: 11 }],
  ])("applies the age-band mix for avg age %i", (age, expected) => {
    const mix = computeDifficultyMix([{ age }], 20);
    expect(mix).toEqual(expected);
  });

  it("forces hard to 0 and folds its share into medium when a player is under 10", () => {
    const mix = computeDifficultyMix([{ age: 5 }], 20);
    expect(mix).toEqual({ easy: 12, medium: 8, hard: 0 });
  });

  it("does not override hard when no player is under 10, even for a young group", () => {
    const mix = computeDifficultyMix([{ age: 10 }], 20);
    expect(mix.hard).toBeGreaterThan(0);
  });

  it.each([1, 7, 10, 13, 20, 37])("always sums to exactly the requested total (%i)", (total) => {
    const players = [{ age: 8 }, { age: 15 }, { age: 42 }];
    const mix = computeDifficultyMix(players, total);
    expect(mix.easy + mix.medium + mix.hard).toBe(total);
  });
});
