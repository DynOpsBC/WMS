import { useDrop } from "react-dnd";
import { PickCardDraggable } from "./PickCardDraggable";
import type { Pick } from "./data/useBcData";

export function PickerColumn({ userId, picks, onReassign }: { userId: string; picks: Pick[]; onReassign: (pickNo: string, userId: string) => void }) {
  const [{ isOver }, drop] = useDrop(() => ({
    accept: "pick",
    drop: (item: { pickNo: string }) => onReassign(item.pickNo, userId),
    collect: (monitor) => ({ isOver: monitor.isOver() }),
  }), [userId, onReassign]);

  return (
    <section ref={drop} className={`picker-column ${isOver ? "picker-column--over" : ""}`}>
      <header>
        <h2>{userId || "Unassigned"}</h2>
        <span>{picks.length}</span>
      </header>
      <div className="picker-column__cards">
        {picks.map((pick) => <PickCardDraggable key={pick.no} pick={pick} />)}
      </div>
    </section>
  );
}
