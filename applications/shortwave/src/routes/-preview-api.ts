import { createServerFn } from "@tanstack/react-start";
import { validateDestination } from "../lib/domain";

export const fetchDestinationPreview = createServerFn({ method: "POST" })
  .validator((destination: string) => {
    if (typeof destination !== "string" || destination.length > 4096) throw new Error("Invalid destination URL.");
    return validateDestination(destination);
  })
  .handler(async ({ data }) => {
    const { auth } = await import("@clerk/tanstack-react-start/server");
    const { userId } = await auth();
    if (!userId) throw new Error("Please sign in to continue.");
    return (await import("../server/preview")).destinationPreview(userId, data);
  });
