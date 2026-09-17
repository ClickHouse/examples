import Link from "next/link";
import { auth } from "@clerk/nextjs/server";
import { getDb } from "../lib/db";
import { listRequests } from "../lib/board";
import {
  BoardError,
  statuses,
  statusLabels,
  parseStatus,
  decodeCursor,
  encodeCursor,
} from "../lib/validation";
import { RequestForm, VoteButton } from "../components/forms";
import { StatusBadge } from "../components/status-badge";

export const dynamic = "force-dynamic";

export default async function Board({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; after?: string }>;
}) {
  const query = await searchParams;
  let status;
  let cursor;
  try {
    status = query.status ? parseStatus(query.status) : undefined;
    cursor = decodeCursor(query.after);
  } catch (error) {
    if (!(error instanceof BoardError)) throw error;
    return (
      <section className="empty-state">
        <h1>That board link is not valid</h1>
        <p>{error.message}</p>
        <Link href="/" className="button button-primary">
          Return to the board
        </Link>
      </section>
    );
  }
  const { userId } = await auth();
  const db = getDb();
  const [results, counts] = await Promise.all([
    listRequests(db, userId, status, cursor),
    db.featureRequest.groupBy({ by: ["status"], _count: true }),
  ]);
  const requests = results.slice(0, 20);
  const total = counts.reduce((sum, item) => sum + item._count, 0);
  const nextCursor =
    results.length > 20 ? encodeCursor(requests[requests.length - 1]) : null;
  const nextParams = new URLSearchParams(status ? { status } : {});
  if (nextCursor) nextParams.set("after", nextCursor);

  return (
    <>
      <section className="hero">
        <div>
          <p className="eyebrow">
            <span /> THE COMMUNITY BOARD
          </p>
          <h1>
            Good ideas start
            <br />
            with <em>you.</em>
          </h1>
          <p className="hero-description">
            Share what would make your work better.
            <br className="desktop-break" /> Vote for the ideas you love. See
            what happens next.
          </p>
        </div>
        <div className="hero-note">
          <span className="note-star" aria-hidden="true">
            ✳
          </span>
          <p>
            One idea can make
            <br />a difference.
          </p>
          <span className="note-line" aria-hidden="true">
            ↙
          </span>
        </div>
      </section>
      <div className="board-layout">
        <section
          aria-labelledby="requests-heading"
          className="request-list-section"
        >
          <div className="section-heading">
            <h2 id="requests-heading">
              Your ideas <span>{total}</span>
            </h2>
            <span className="sort-label">Newest first</span>
          </div>
          <nav className="filter-bar" aria-label="Filter requests by status">
            <Link
              href="/"
              className={`filter ${!status ? "active" : ""}`}
              aria-current={!status ? "page" : undefined}
            >
              All ideas <span>{total}</span>
            </Link>
            {statuses.map((value) => (
              <Link
                key={value}
                href={`/?status=${value}`}
                className={`filter ${status === value ? "active" : ""}`}
                aria-current={status === value ? "page" : undefined}
              >
                {statusLabels[value]}{" "}
                <span>
                  {counts.find((item) => item.status === value)?._count ?? 0}
                </span>
              </Link>
            ))}
          </nav>
          <div className="request-list">
            {requests.length ? (
              requests.map((request) => (
                <article key={request.id} className="request-card">
                  <VoteButton
                    id={request.id}
                    title={request.title}
                    count={request._count.votes}
                    voted={request.votes.length > 0}
                    signedIn={Boolean(userId)}
                  />
                  <div className="request-summary">
                    <StatusBadge status={request.status} />
                    <h3>
                      <Link href={`/requests/${request.id}`}>
                        {request.title}
                      </Link>
                    </h3>
                    <p className="request-preview">{request.description}</p>
                    <div className="request-meta">
                      <span className="avatar" aria-hidden="true">
                        {request.authorName[0].toUpperCase()}
                      </span>
                      <span>{request.authorName}</span>
                      <span aria-hidden="true">·</span>
                      <time dateTime={request.createdAt.toISOString()}>
                        {request.createdAt.toLocaleDateString("en-GB", {
                          day: "numeric",
                          month: "short",
                          year: "numeric",
                          timeZone: "UTC",
                        })}
                      </time>
                    </div>
                  </div>
                  <Link
                    className="card-arrow"
                    href={`/requests/${request.id}`}
                    aria-label={`Read ${request.title}`}
                  >
                    ↗
                  </Link>
                </article>
              ))
            ) : (
              <div className="empty-state">
                <span aria-hidden="true">✳</span>
                <h3>
                  {cursor
                    ? "You’re all caught up"
                    : "Room for the next good idea"}
                </h3>
                <p>
                  {cursor
                    ? "There are no more requests in this view."
                    : "No requests here yet. Share a suggestion to get things started."}
                </p>
                {cursor && (
                  <Link href={status ? `/?status=${status}` : "/"}>
                    Back to newest ideas
                  </Link>
                )}
              </div>
            )}
          </div>
          {nextCursor && (
            <Link
              className="button button-secondary pagination"
              href={`/?${nextParams}`}
            >
              Older ideas <span aria-hidden="true">↓</span>
            </Link>
          )}
        </section>
        <aside className="submission-panel" aria-labelledby="submit-heading">
          <div className="panel-heading">
            <span className="plus-icon" aria-hidden="true">
              +
            </span>
            <p className="eyebrow">HAVE SOMETHING IN MIND?</p>
            <h2 id="submit-heading">Make a suggestion.</h2>
            <p>
              The best improvements begin with a real problem. We’d love to hear
              yours.
            </p>
          </div>
          {userId ? (
            <RequestForm />
          ) : (
            <div className="sign-in-prompt">
              <Link href="/sign-in" className="button button-primary">
                Sign in to share an idea <span aria-hidden="true">↗</span>
              </Link>
              <p>You can browse freely. Sign in to post and vote.</p>
            </div>
          )}
          <div className="panel-footnote">
            <span aria-hidden="true">↗</span>
            <p>
              A little context goes a long way. Tell us <strong>why</strong> it
              matters to you.
            </p>
          </div>
        </aside>
      </div>
    </>
  );
}
