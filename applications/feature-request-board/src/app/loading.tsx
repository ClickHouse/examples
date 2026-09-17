export default function Loading() {
  return (
    <div className="empty-state" role="status">
      <span className="loading-mark" aria-hidden="true">
        ✳
      </span>
      <p>Gathering your ideas…</p>
    </div>
  );
}
