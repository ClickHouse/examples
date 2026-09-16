import { createFileRoute, redirect } from "@tanstack/react-router";
import { AppShell } from "../components/shell";
import { checkSession } from "./-api";
export const Route = createFileRoute("/_app")({
  beforeLoad: async () => {
    if (!(await checkSession())) throw redirect({ to: "/sign-in/$" });
  },
  component: AppShell,
});
