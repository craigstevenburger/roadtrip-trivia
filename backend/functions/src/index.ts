import * as admin from "firebase-admin";

admin.initializeApp();

export {
  createGame,
  joinGame,
  setDriver,
  startGame,
  submitAnswer,
  advanceQuestion,
  pauseGame,
  resumeGame,
  cleanupStaleGames,
} from "./gameFunctions";
