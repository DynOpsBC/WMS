// Geri al / ileri al: tasarımın değişmez anlık görüntüleri.
import type { LabelDesign } from "../model/types";

export interface HistoryState {
  present: LabelDesign;
  past: LabelDesign[];
  future: LabelDesign[];
  /** sürükleme/boyutlandırma başındaki görüntü (bitince geçmişe yazılır) */
  gestureBase: LabelDesign | null;
  /** art arda yazılan aynı alan tek adımda birleşir */
  lastKey: string | null;
  lastAt: number;
}

export type HistoryAction =
  | { type: "load"; design: LabelDesign }
  | { type: "commit"; update: (d: LabelDesign) => LabelDesign; key?: string; at?: number }
  | { type: "gestureBegin" }
  | { type: "gestureUpdate"; update: (d: LabelDesign) => LabelDesign }
  | { type: "gestureEnd" }
  | { type: "undo" }
  | { type: "redo" };

const LIMIT = 100;
const COALESCE_MS = 1200;

export function initHistory(design: LabelDesign): HistoryState {
  return { present: design, past: [], future: [], gestureBase: null, lastKey: null, lastAt: 0 };
}

function pushPast(past: LabelDesign[], d: LabelDesign): LabelDesign[] {
  const next = [...past, d];
  return next.length > LIMIT ? next.slice(next.length - LIMIT) : next;
}

export function historyReducer(state: HistoryState, action: HistoryAction): HistoryState {
  switch (action.type) {
    case "load":
      return initHistory(action.design);
    case "commit": {
      const next = action.update(state.present);
      if (next === state.present) return state;
      const at = action.at ?? Date.now();
      const coalesce = action.key !== undefined && action.key === state.lastKey && at - state.lastAt < COALESCE_MS;
      return {
        ...state,
        present: next,
        past: coalesce ? state.past : pushPast(state.past, state.present),
        future: [],
        lastKey: action.key ?? null,
        lastAt: at,
      };
    }
    case "gestureBegin":
      return { ...state, gestureBase: state.present };
    case "gestureUpdate": {
      const next = action.update(state.present);
      return next === state.present ? state : { ...state, present: next };
    }
    case "gestureEnd": {
      const base = state.gestureBase;
      if (!base) return state;
      if (base === state.present) return { ...state, gestureBase: null };
      return { ...state, past: pushPast(state.past, base), future: [], gestureBase: null, lastKey: null };
    }
    case "undo": {
      if (state.past.length === 0) return state;
      const prev = state.past[state.past.length - 1];
      return { ...state, present: prev, past: state.past.slice(0, -1), future: [state.present, ...state.future], lastKey: null };
    }
    case "redo": {
      if (state.future.length === 0) return state;
      const [next, ...rest] = state.future;
      return { ...state, present: next, past: pushPast(state.past, state.present), future: rest, lastKey: null };
    }
  }
}
