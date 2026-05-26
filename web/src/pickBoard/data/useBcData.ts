import { useEffect, useState } from "react";
import { requestRefresh } from "../../../al-bridge/ControlAddInBridge";

export type Pick = {
  no: string;
  sourceNo: string;
  assignedUserId: string;
  status: "Open" | "InProgress" | "Done" | string;
  percentComplete: number;
  dueDate?: string;
};

export type PickBoardData = { picks: Pick[] };

const seed: Pick[] = [
  { no: "PICK-S5-0001", sourceNo: "SHIP-1001", assignedUserId: "MOBILE", status: "Open", percentComplete: 15, dueDate: "2026-05-27" },
  { no: "PICK-S5-0002", sourceNo: "SHIP-1002", assignedUserId: "ADA", status: "InProgress", percentComplete: 45, dueDate: "2026-05-27" },
  { no: "PICK-S5-0003", sourceNo: "SHIP-1003", assignedUserId: "MERT", status: "Open", percentComplete: 0, dueDate: "2026-05-28" },
];

export function useBcData(initialData?: PickBoardData) {
  const [data, setData] = useState<PickBoardData>(initialData ?? { picks: seed });

  useEffect(() => {
    const load = async () => {
      try {
        const response = await fetch("/picks?$filter=status eq 'Open' or status eq 'InProgress'");
        if (response.ok) {
          const json = await response.json();
          setData({ picks: json.value ?? json.picks ?? seed });
        } else {
          requestRefresh();
        }
      } catch {
        requestRefresh();
      }
    };
    const id = window.setInterval(load, 5000);
    return () => window.clearInterval(id);
  }, []);

  return { data, setData };
}
