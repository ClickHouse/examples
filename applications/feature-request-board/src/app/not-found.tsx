import Link from "next/link";
export default function NotFound() {
  return (
    <div className="empty-state">
      <p className="eyebrow">NOT FOUND</p>
      <h1>This idea is no longer here.</h1>
      <p>The request may have been removed, or the link may be incorrect.</p>
      <Link href="/" className="button button-primary">
        Back to the board
      </Link>
    </div>
  );
}
