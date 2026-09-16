import { createFileRoute } from "@tanstack/react-router";
import { UserProfile } from "@clerk/tanstack-react-start";
import { SectionHeading } from "../components/ui";
export const Route = createFileRoute("/_app/account")({
  component: () => (
    <>
      <SectionHeading title="Account" />
      <div className="account-profile">
        <UserProfile routing="hash" />
      </div>
    </>
  ),
});
