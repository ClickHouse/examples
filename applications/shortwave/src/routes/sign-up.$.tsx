import { createFileRoute } from "@tanstack/react-router";
import { SignUp } from "@clerk/tanstack-react-start";
import { Brand } from "../components/ui";
import { AuthUnavailable } from "../components/shell";
export const Route = createFileRoute("/sign-up/$")({
  component: () =>
    import.meta.env.VITE_CLERK_PUBLISHABLE_KEY ? (
      <div className="auth-screen">
        <Brand />
        <SignUp routing="path" path="/sign-up" signInUrl="/sign-in" />
      </div>
    ) : (
      <AuthUnavailable />
    ),
});
