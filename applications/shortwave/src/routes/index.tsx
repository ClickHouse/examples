import { useUser } from "@clerk/tanstack-react-start";
import { createFileRoute } from "@tanstack/react-router";
import {
  ArrowUpRight,
  BarChart3,
  Link2,
  QrCode,
  ScanLine,
} from "lucide-react";
import { Brand } from "../components/ui";
export const Route = createFileRoute("/")({ component: Landing });

function NavigationAction() {
  if (!import.meta.env.VITE_CLERK_PUBLISHABLE_KEY) {
    return <AccountAction signedIn={false} />;
  }
  return <SessionNavigationAction />;
}

function SessionNavigationAction() {
  const { isLoaded, isSignedIn } = useUser();
  if (!isLoaded) {
    return (
      <button className="button-primary button-small" disabled>
        Loading…
      </button>
    );
  }
  return <AccountAction signedIn={isSignedIn === true} />;
}

function AccountAction({ signedIn }: { signedIn: boolean }) {
  return (
    <a
      className="button-primary button-small"
      href={signedIn ? "/links" : "/sign-up"}
    >
      {signedIn ? "Dashboard" : "Get started"} <ArrowUpRight size={16} />
    </a>
  );
}

function Landing() {
  return (
    <div className="landing">
      <header className="landing-nav">
        <Brand />
        <nav aria-label="Main navigation">
          <NavigationAction />
        </nav>
      </header>
      <main>
        <section className="hero">
          <div className="hero-copy">
            <h1>
              Small links.
              <br />
              <span>Big energy.</span>
            </h1>
            <p>
              Turn a long URL into your next great connection.
              <br className="desktop-only" /> Memorable links, custom QR codes,
              and a clearer
              <br className="desktop-only" /> picture of what’s working. All in
              one place.
            </p>
            <a href="/sign-up" className="button-primary hero-cta">
              Make your first link <ArrowUpRight size={19} />
            </a>
          </div>
          <div className="hero-art" aria-hidden="true">
            <div className="orbital orbital-one" />
            <div className="orbital orbital-two" />
            <div className="signal-point point-one" />
            <div className="signal-point point-two" />
            <div className="link-token">
              <Link2 size={80} strokeWidth={1.6} />
            </div>
            <div className="floating-card card-url">
              <span className="card-icon">
                <Link2 size={19} />
              </span>
              <div>
                <small>LESS URL. MORE YOU.</small>
                <strong>your next big thing ↗</strong>
              </div>
            </div>
            <div className="floating-card card-qr">
              <ScanLine size={30} />
              <span>Take it offline.</span>
              <ArrowUpRight size={17} />
            </div>
          </div>
        </section>
        <section className="features" id="possibilities">
          {[
            {
              icon: Link2,
              title: "Make it yours.",
              text: "Shorten, customize, and organize. Give every destination a link worth sharing.",
            },
            {
              icon: QrCode,
              title: "Go beyond the screen.",
              text: "Create a QR code with your colors and logo. Print it, share it, take it anywhere.",
            },
            {
              icon: BarChart3,
              title: "Find your signal.",
              text: "See the clicks, campaigns, and connections that move your story forward.",
            },
          ].map(({ icon: Icon, title, text }) => (
            <article className="feature" key={title}>
              <div className="feature-top">
                <Icon size={25} />
              </div>
              <h2>{title}</h2>
              <p>{text}</p>
            </article>
          ))}
        </section>
      </main>
      <footer className="landing-footer">
        <Brand />
        <span>© {new Date().getFullYear()} Shortwave</span>
      </footer>
    </div>
  );
}
