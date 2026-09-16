# Custom domains

The deployer configures hostnames they control. Use app.mydomain.com for the
application and mydomain.com for short links, or go.mydomain.com if the apex
already hosts another website. The registrar can differ from the DNS provider;
the reference Workers deployment requires an active owned Cloudflare zone.

## Connect a hostname

1. Configure the app origin and short hostname in the private deployment inputs.
2. Attach both exact names as Workers Custom Domains. Cloudflare supplies routing
   DNS and certificates. Resolve conflicting records deliberately and preserve
   mail and unrelated website records. Follow
   [Cloudflare's instructions](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/).
3. Deploy and verify public HTTPS for both names. APP_URL is the dashboard origin;
   PUBLIC_CUSTOM_DOMAINS contains short hostnames, excluding the dashboard.
4. Sign in, open Domains, and add the exact short hostname. Copy its generated TXT
   name and value into DNS. For mydomain.com the name is
   _shortwave-verification.mydomain.com; for go.mydomain.com it is
   _shortwave-verification.go.mydomain.com. Select Check DNS after propagation.
5. Select the verified domain when creating a link. Visit the copied URL signed
   out, decode the downloaded QR, edit the destination, then disable the link.
   Confirm 302 redirects after edits and 410 after disabling.

See the [deployment walkthrough](setup-plan.md) for the provisioning commands.

## Three independent conditions

| Condition | Meaning | How to verify |
| --- | --- | --- |
| Ownership | A signed-in account controls the DNS challenge | App TXT check |
| Routing | Requests reach the intended Worker | Cloudflare domain configuration and public request |
| HTTPS | The hostname has a valid served certificate | Public HTTPS smoke check |

The app's Ready for links state combines verified ownership with the configured
hosting allowlist. It is not a live certificate probe. Deploy-time verification
must establish routing and HTTPS independently.

DNS is configured per hostname, never per short link. Individual destinations
are Postgres rows resolved at /r/:slug. The short-domain root redirects to the
app; app pages are not served on short-only hostnames.

## Ownership and lifecycle

Claims are account-scoped, with one verified owner per canonical hostname.
Rechecking a missing or mismatched TXT record returns a claim to pending;
temporary resolver errors preserve the previous ownership state and report the
error. Checks are manual; retain the TXT record for later rechecks.

A link's domain assignment and slug are immutable. The same slug can exist in
separate hostname namespaces. A domain with referenced links cannot be removed,
including when those links are disabled. Do not detach routing for a hostname
while its printed links are expected to remain usable.

Removing a claim in the app does not delete provider resources. Removing a
Workers Custom Domain does not delete a Postgres claim. An operator must manage
both parts deliberately. Automatic onboarding of other customers' domains,
certificate polling, periodic ownership checks, and provider cleanup are future
extensions, not capabilities of this example.
