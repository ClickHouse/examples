import Link from "next/link";
import { notFound } from "next/navigation";
import { auth } from "@clerk/nextjs/server";
import { getDb } from "../../../lib/db";
import {
  parseRequestId,
  isMaintainer,
  BoardError,
} from "../../../lib/validation";
import {
  VoteButton,
  RequestForm,
  StatusForm,
  DeleteForm,
} from "../../../components/forms";
import { StatusBadge } from "../../../components/status-badge";

export const dynamic = "force-dynamic";

export default async function RequestDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  try {
    parseRequestId(id);
  } catch (error) {
    if (error instanceof BoardError) notFound();
    throw error;
  }
  const { userId } = await auth();
  const request = await getDb().featureRequest.findUnique({
    where: { id },
    include: {
      _count: { select: { votes: true } },
      votes: { where: { userId: userId ?? "" }, select: { requestId: true } },
    },
  });
  if (!request) notFound();
  const owner = request.authorId === userId;

  return (
    <div className="detail-page">
      <Link href="/" className="back-link">
        <span aria-hidden="true">←</span> All ideas
      </Link>
      <div className="detail-layout">
        <article className="detail-card">
          <StatusBadge status={request.status} />
          <h1>{request.title}</h1>
          <div className="request-meta">
            <span className="avatar" aria-hidden="true">
              {request.authorName[0].toUpperCase()}
            </span>
            <span>{request.authorName}</span>
            <span aria-hidden="true">·</span>
            <time dateTime={request.createdAt.toISOString()}>
              {request.createdAt.toLocaleDateString("en-GB", {
                day: "numeric",
                month: "long",
                year: "numeric",
                timeZone: "UTC",
              })}
            </time>
          </div>
          <p className="request-body">{request.description}</p>
          <div className="detail-vote">
            <VoteButton
              id={id}
              title={request.title}
              count={request._count.votes}
              voted={request.votes.length > 0}
              signedIn={Boolean(userId)}
            />
            <div>
              <strong>Would this help you too?</strong>
              <p>Add your vote to help shape what comes next.</p>
            </div>
          </div>
        </article>
        <aside className="detail-sidebar">
          <p className="eyebrow">A SHARED ROADMAP</p>
          <h2>Your voice counts.</h2>
          <p>
            Each person gets one vote per idea. You can change your mind at any
            time.
          </p>
          <p>Status updates come from the board’s maintainers.</p>
          {isMaintainer(userId) && (
            <StatusForm id={id} status={request.status} />
          )}
        </aside>
      </div>
      {owner && (
        <section className="owner-panel" aria-labelledby="edit-heading">
          <div>
            <p className="eyebrow">YOUR REQUEST</p>
            <h2 id="edit-heading">Refine your idea.</h2>
            <p>
              You can edit the title and description, or remove the request and
              its votes.
            </p>
            <DeleteForm id={id} />
          </div>
          <RequestForm
            request={{
              id: request.id,
              title: request.title,
              description: request.description,
            }}
          />
        </section>
      )}
    </div>
  );
}
