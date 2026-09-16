import { createServerFn } from "@tanstack/react-start";
import type {
  AnalyticsFilter,
  LinkInput,
  QrStyle,
  UtmValues,
} from "../lib/types";

async function user() {
  const { auth } = await import("@clerk/tanstack-react-start/server");
  const { userId } = await auth();
  if (!userId) throw new Error("Please sign in to continue.");
  return userId;
}

export const checkSession = createServerFn({ method: "GET" }).handler(
  async () => {
    const { auth } = await import("@clerk/tanstack-react-start/server");
    return Boolean((await auth()).userId);
  },
);

export const fetchLinks = createServerFn({ method: "GET" })
  .validator((data: { search?: string; tag?: string; folderId?: string | null }) => data)
  .handler(async ({ data }) => {
    const userId = await user();
    const service = await import("../server/service");
    return service.listLinks(userId, data);
  });
export const fetchLink = createServerFn({ method: "GET" })
  .validator((id: string) => id)
  .handler(async ({ data }) => {
    const userId = await user();
    return (await import("../server/service")).getLink(userId, data);
  });
export const fetchTags = createServerFn({ method: "GET" })
  .validator((query: string) => query)
  .handler(async ({ data }) => {
    const userId = await user();
    return (await import("../server/service")).listTags(userId, data);
  });
export const saveLink = createServerFn({ method: "POST" })
  .validator((data: { id?: string; input: LinkInput }) => data)
  .handler(async ({ data }) => {
    const userId = await user();
    const service = await import("../server/service");
    return data.id
      ? service.updateLink(userId, data.id, data.input)
      : service.createLink(userId, data.input);
  });
export const fetchTemplates = createServerFn({ method: "GET" }).handler(
  async () => {
    const userId = await user();
    return (await import("../server/service")).listTemplates(userId);
  },
);
export const saveTemplate = createServerFn({ method: "POST" })
  .validator((data: { id?: string; name: string; values: UtmValues }) => data)
  .handler(async ({ data }) => {
    const userId = await user();
    const service = await import("../server/service");
    return data.id
      ? service.updateTemplate(userId, data.id, {
          name: data.name,
          values: data.values,
        })
      : service.createTemplate(userId, {
          name: data.name,
          values: data.values,
        });
  });
export const removeTemplate = createServerFn({ method: "POST" })
  .validator((id: string) => id)
  .handler(async ({ data }) => {
    const userId = await user();
    return (await import("../server/service")).deleteTemplate(userId, data);
  });
export const saveQr = createServerFn({ method: "POST" })
  .validator((data: { linkId: string; style: QrStyle }) => data)
  .handler(async ({ data }) => {
    const userId = await user();
    return (await import("../server/service")).saveQrStyle(
      userId,
      data.linkId,
      data.style,
    );
  });
export const fetchAnalytics = createServerFn({ method: "GET" })
  .validator((data: AnalyticsFilter) => data)
  .handler(async ({ data }) => {
    const userId = await user();
    return (await import("../server/analytics")).getAnalytics(userId, data);
  });

export const fetchFolders = createServerFn({ method: "GET" }).handler(async () => {
  const userId = await user();
  return (await import("../server/service")).listFolders(userId);
});
export const saveFolder = createServerFn({ method: "POST" })
  .validator((data: { id?: string; name: string }) => data)
  .handler(async ({ data }) => {
    const userId = await user();
    const service = await import("../server/service");
    return data.id ? service.updateFolder(userId, data.id, data.name) : service.createFolder(userId, data.name);
  });
export const removeFolder = createServerFn({ method: "POST" })
  .validator((id: string) => id)
  .handler(async ({ data }) => {
    const userId = await user();
    return (await import("../server/service")).deleteFolder(userId, data);
  });
