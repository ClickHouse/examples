import { createServerFn } from "@tanstack/react-start";

async function user() {
  const { auth } = await import("@clerk/tanstack-react-start/server");
  const { userId } = await auth();
  if (!userId) throw new Error("Please sign in to continue.");
  return userId;
}

function domainId(value: string) {
  if (typeof value !== "string" || !/^[0-9a-f-]{36}$/i.test(value)) {
    throw new Error("Invalid domain.");
  }
  return value;
}

export const fetchDomains = createServerFn({ method: "GET" }).handler(async () => {
  const userId = await user();
  return (await import("../server/custom-domains")).listDomains(userId);
});

export const addDomain = createServerFn({ method: "POST" })
  .validator((hostname: string) => {
    if (typeof hostname !== "string" || hostname.length > 1024) {
      throw new Error("Enter a valid domain name.");
    }
    return hostname;
  })
  .handler(async ({ data }) => {
    const userId = await user();
    return (await import("../server/custom-domains")).addDomain(userId, data);
  });

export const checkDomainDns = createServerFn({ method: "POST" })
  .validator(domainId)
  .handler(async ({ data }) => {
    const userId = await user();
    return (await import("../server/custom-domains")).verifyDomain(userId, data);
  });

export const removeDomain = createServerFn({ method: "POST" })
  .validator(domainId)
  .handler(async ({ data }) => {
    const userId = await user();
    return (await import("../server/custom-domains")).removeDomain(userId, data);
  });
