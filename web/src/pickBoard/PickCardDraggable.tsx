import { useDrag } from "react-dnd";
import type { Pick } from "./data/useBcData";

export function PickCardDraggable({ pick }: { pick: Pick }) {
  const [{ isDragging }, drag] = useDrag(() => ({
    type: "pick",
    item: { pickNo: pick.no },
    collect: (monitor) => ({ isDragging: monitor.isDragging() }),
  }), [pick.no]);

  return (
    <article ref={drag} className="pick-card" style={{ opacity: isDragging ? 0.45 : 1 }}>
      <div className="pick-card__top">
        <strong>{pick.no}</strong>
        <span>{pick.status}</span>
      </div>
      <div className="pick-card__source">{pick.sourceNo}</div>
      <div className="pick-card__progress"><span style={{ width: `${pick.percentComplete}%` }} /></div>
      <div className="pick-card__due">{pick.dueDate ?? ""}</div>
    </article>
  );
}
