import type { Metadata } from "next";
import Link from "next/link";
import { ClerkProvider, Show, UserButton } from "@clerk/nextjs";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "Feature Board · A little better, together",
    template: "%s · Feature Board",
  },
  description:
    "Share ideas, vote for what matters, and follow what is coming next. A Next.js and Prisma example on ClickHouse Managed Postgres.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <ClerkProvider>
      <html lang="en">
        <body>
          <a className="skip-link" href="#main">
            Skip to content
          </a>
          <header className="site-header">
            <div className="header-inner">
              <Link href="/" className="brand" aria-label="Feature Board home">
                <span className="brand-mark" aria-hidden="true">
                  f<span>↗</span>
                </span>
                <span>Feature Board</span>
              </Link>
              <span className="header-caption">A little better, together.</span>
              <nav className="account-nav" aria-label="Account">
                <Show when="signed-out">
                  <Link className="sign-in-link" href="/sign-in">
                    Sign in <span aria-hidden="true">↗</span>
                  </Link>
                </Show>
                <Show when="signed-in">
                  <UserButton />
                </Show>
              </nav>
            </div>
          </header>
          <main id="main" className="main-shell">
            {children}
          </main>
          <footer className="site-footer">
            <span>Small ideas. Meaningful improvements.</span>
            <a href="https://clickhouse.com/cloud/postgres">
              Built on ClickHouse Managed Postgres{" "}
              <span aria-hidden="true">↗</span>
            </a>
          </footer>
        </body>
      </html>
    </ClerkProvider>
  );
}
