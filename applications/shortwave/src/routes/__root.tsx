import { ClerkProvider } from "@clerk/tanstack-react-start";
import { ClickUIProvider, InitCUIThemeScript } from "@clickhouse/click-ui";
import { createRootRoute, HeadContent, Scripts } from "@tanstack/react-router";
import type { ReactNode } from "react";
import appCss from "../styles.css?url";

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "Shortwave" },
      {
        name: "description",
        content:
          "Create and manage short links, QR codes, and click analytics.",
      },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "icon", type: "image/svg+xml", href: "/favicon.svg" },
    ],
  }),
  shellComponent: RootDocument,
  notFoundComponent: () => (
    <div className="page-message">
      <h1>This link went off air.</h1>
      <p>The page you’re looking for doesn’t exist.</p>
      <a className="button-primary" href="/">
        Back to Shortwave
      </a>
    </div>
  ),
  errorComponent: () => (
    <div className="page-message">
      <h1>Something interrupted the signal.</h1>
      <p>Please reload and try again.</p>
      <a className="button-primary" href="/">
        Back to Shortwave
      </a>
    </div>
  ),
});

function RootDocument({ children }: { children: ReactNode }) {
  const content = (
    <ClickUIProvider theme="dark" persistTheme>
      {children}
    </ClickUIProvider>
  );
  return (
    <html lang="en">
      <head>
        <HeadContent />
        <InitCUIThemeScript defaultTheme="dark" />
      </head>
      <body>
        {import.meta.env.VITE_CLERK_PUBLISHABLE_KEY ? (
          <ClerkProvider
            allowedRedirectOrigins={[]}
            signInUrl="/sign-in"
            signUpUrl="/sign-up"
            signInFallbackRedirectUrl="/links"
            signUpFallbackRedirectUrl="/links"
            appearance={{
              variables: {
                colorPrimary: "#faff69",
                colorPrimaryForeground: "#181910",
                colorBackground: "#1a1b1e",
                colorForeground: "#f3f3f3",
                colorNeutral: "#f3f3f3",
                borderRadius: "0.65rem",
              },
              elements: {
                userButtonPopoverActionButton: {
                  color: "#f3f3f3",
                  "&:hover": {
                    color: "#f3f3f3",
                    backgroundColor: "#303136",
                  },
                  "&:focus-visible": {
                    color: "#f3f3f3",
                    backgroundColor: "#303136",
                    outline: "2px solid #faff69",
                    outlineOffset: "-2px",
                  },
                },
              },
            }}
          >
            {content}
          </ClerkProvider>
        ) : (
          content
        )}
        <Scripts />
      </body>
    </html>
  );
}
