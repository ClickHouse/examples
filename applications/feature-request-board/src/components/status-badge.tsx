import { statusLabels, type Status } from "../lib/validation";

export function StatusBadge({ status }: { status: Status }) {
  return (
    <span className={`status-badge status-${status.toLowerCase()}`}>
      <span aria-hidden="true" />
      {statusLabels[status]}
    </span>
  );
}
