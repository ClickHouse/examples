"use client";

import { Link } from "@clickhouse/click-ui";
import NextLink from "next/link";

// Click UI's `component` prop takes a component, which a Server Component
// cannot pass to a Client Component, so the pairing with next/link lives here.
export function AppLink({
  href,
  children,
}: {
  href: string;
  children: React.ReactNode;
}) {
  return (
    <Link component={NextLink} href={href}>
      {children}
    </Link>
  );
}
