import { useCallback, useEffect, useMemo, useState } from "react";
import { DndProvider } from "react-dnd";
import { HTML5Backend } from "react-dnd-html5-backend";
import { listenBridge } from "../../al-bridge/ControlAddInBridge";
import { reassignPick } from "./ReassignMutation";
import { PickerColumn } from "./PickerColumn";
import { type PickBoardData, useBcData } from "./data/useBcData";
import en from "./i18n/en";
import tr from "./i18n/tr";
import de from "./i18n/de";
import "./styles.css";

const dictionaries = { en, tr, de };

export function PickBoardApp() {
  const { data, setData } = useBcData();
  const [locale, setLocale] = useState<keyof typeof dictionaries>("en");

  useEffect(() => listenBridge((message) => {
    if (message.type === "setData") setData(normalizeData(message.payload));
    if (message.type === "setLocale") setLocale(message.locale.startsWith("tr") ? "tr" : message.locale.startsWith("de") ? "de" : "en");
  }), [setData]);

  const byPicker = useMemo(() => {
    const map = new Map<string, typeof data.picks>();
    data.picks.forEach((pick) => {
      const key = pick.assignedUserId || "";
      map.set(key, [...(map.get(key) ?? []), pick]);
    });
    return [...map.entries()].sort(([a], [b]) => a.localeCompare(b));
  }, [data.picks]);

  const onReassign = useCallback((pickNo: string, userId: string) => {
    setData((current) => ({
      picks: current.picks.map((pick) => pick.no === pickNo ? { ...pick, assignedUserId: userId, status: "InProgress" } : pick),
    }));
    reassignPick(pickNo, userId);
  }, [setData]);

  const t = dictionaries[locale];

  return (
    <DndProvider backend={HTML5Backend}>
      <main className="pick-board">
        <header className="pick-board__header">
          <h1>{t.title}</h1>
          <span>{data.picks.length} picks</span>
        </header>
        {data.picks.length === 0 ? <p className="pick-board__empty">{t.empty}</p> : (
          <div className="pick-board__columns">
            {byPicker.map(([userId, picks]) => (
              <PickerColumn key={userId || "unassigned"} userId={userId} picks={picks} onReassign={onReassign} />
            ))}
          </div>
        )}
      </main>
    </DndProvider>
  );
}

function normalizeData(payload: unknown): PickBoardData {
  if (typeof payload === "string") {
    try {
      return normalizeData(JSON.parse(payload));
    } catch {
      return { picks: [] };
    }
  }
  const candidate = payload as Partial<PickBoardData> | undefined;
  return { picks: Array.isArray(candidate?.picks) ? candidate.picks : [] };
}
