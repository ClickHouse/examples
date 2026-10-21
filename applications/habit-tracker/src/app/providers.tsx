"use client";

import { ClickUIProvider } from "@clickhouse/click-ui";

export function Providers({ children }: { children: React.ReactNode }) {
  return <ClickUIProvider theme="dark">{children}</ClickUIProvider>;
}
