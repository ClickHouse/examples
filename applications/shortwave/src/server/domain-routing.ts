import { runtimeEnvironment } from "./runtime";

/** Hosting configuration is trusted server state, separate from DNS ownership. */
export function isCustomDomainHosted(hostname: string): boolean {
  return (runtimeEnvironment("PUBLIC_CUSTOM_DOMAINS") || "").split(",")
    .some((value) => value.trim().toLowerCase() === hostname);
}

export function defaultLinkHostname(): string {
  return new URL(runtimeEnvironment("APP_URL") || "http://localhost:4317").hostname.toLowerCase();
}
