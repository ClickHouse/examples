import { createFileRoute } from "@tanstack/react-router";
import { SignIn } from "@clerk/tanstack-react-start";
import { Brand } from "../components/ui";
import { AuthUnavailable } from "../components/shell";
export const Route = createFileRoute("/sign-in/$")({
  component: () =>
    import.meta.env.VITE_CLERK_PUBLISHABLE_KEY ? (
      <div className="auth-screen">
        <Brand />
        <SignIn routing="path" path="/sign-in" signUpUrl="/sign-up" />
      </div>
    ) : (
      <AuthUnavailable />
    ),
});
