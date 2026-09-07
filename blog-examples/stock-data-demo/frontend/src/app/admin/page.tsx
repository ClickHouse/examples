"use client";
import { ClickUIProvider } from "@clickhouse/click-ui";
import AdminView from "@/components/AdminView";

export default function AdminPage() {
  return (
    <ClickUIProvider theme="dark">
      <AdminView />
    </ClickUIProvider>
  );
}
