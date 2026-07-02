export type GameStatus = "waiting" | "active" | "paused" | "completed";
export type Difficulty = "easy" | "medium" | "hard";
export type AgeTier = "child" | "teen" | "adult";

export interface QuestionDoc {
  id: string;
  category: string;
  difficulty: Difficulty;
  question: string;
  correctAnswer: string;
  options: string[];
}

export interface PlayerAnswer {
  choice: string | null;
  correct: boolean;
  pointsEarned: number;
  answeredAt: FirebaseFirestore.Timestamp;
}

export interface PlayerDoc {
  displayName: string;
  age: number;
  ageTier: AgeTier;
  isDriver: boolean;
  score: number;
  answers: Record<string, PlayerAnswer>;
}

export interface GameDoc {
  status: GameStatus;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
  pausedAt: FirebaseFirestore.Timestamp | null;
  currentQuestionIndex: number;
  questionStartedAt: FirebaseFirestore.Timestamp | null;
  hostDeviceId: string;
  driverPlayerId: string | null;
  questions: QuestionDoc[];
  players: Record<string, PlayerDoc>;
  expiresAt: FirebaseFirestore.Timestamp;
}

export const QUESTIONS_PER_GAME = 20;
export const ANSWER_WINDOW_SECONDS = 20;
export const REST_STOP_TTL_HOURS = 4;
export const WAITING_GAME_TTL_HOURS = 2;
export const COMPLETED_GAME_GRACE_MINUTES = 5;
