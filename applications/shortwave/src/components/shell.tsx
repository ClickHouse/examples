import { useUser, UserButton } from "@clerk/tanstack-react-start";
import { Link, Outlet } from "@tanstack/react-router";
import {
  ArrowUpRight,
  BarChart3,
  Folder,
  Globe,
  Link2,
  Menu,
  SlidersHorizontal,
  UserRound,
  X,
} from "lucide-react";
import { useState, type ReactNode } from "react";
import { Brand, Loading } from "./ui";
import { WorkspaceShortcutProvider, WorkspaceShortcuts } from "./workspace-shortcuts";

export function AuthGate({ children }: { children: ReactNode }) {
  if (!import.meta.env.VITE_CLERK_PUBLISHABLE_KEY) return <AuthUnavailable />;
  return <Authenticated>{children}</Authenticated>;
}
function Authenticated({ children }: { children: ReactNode }) {
  const { isLoaded, isSignedIn } = useUser();
  if (!isLoaded) return <Loading />;
  if (!isSignedIn)
    return (
      <div className="auth-screen">
        <Brand />
        <div className="auth-prompt">
          <h1>Sign in</h1>
          <a className="button-primary" href="/sign-in">
            Sign in <ArrowUpRight size={18} />
          </a>
          <p>
            New here?{" "}
            <a href="/sign-up" className="text-link">
              Create an account
            </a>
          </p>
        </div>
      </div>
    );
  return children;
}
export function AuthUnavailable() {
  return (
    <div className="auth-screen">
      <Brand />
      <div className="auth-prompt">
        <h1>Account access unavailable</h1>
        <p>
          Account access hasn’t been configured for this instance yet. Please
          check back soon.
        </p>
        <a href="/" className="button-secondary">
          Back to home
        </a>
      </div>
    </div>
  );
}
export function AppShell() {
  return (
    <AuthGate>
      <WorkspaceShortcutProvider><SignedInShell /></WorkspaceShortcutProvider>
    </AuthGate>
  );
}
function SignedInShell() {
  const [mobile, setMobile] = useState(false);
  const { user } = useUser();
  const nav = [
    { to: "/links", label: "Links", icon: Link2 },
    { to: "/analytics", label: "Analytics", icon: BarChart3 },
    { to: "/templates", label: "UTM templates", icon: SlidersHorizontal },
    { to: "/folders", label: "Folders", icon: Folder },
    { to: "/domains", label: "Domains", icon: Globe },
    { to: "/account", label: "Account", icon: UserRound },
  ] as const;
  return (
    <div className="app-shell">
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <div className="mobile-header">
        <Brand />
        <button
          className="icon-button"
          aria-label={mobile ? "Close navigation" : "Open navigation"}
          aria-expanded={mobile}
          onClick={() => setMobile(!mobile)}
        >
          {mobile ? <X /> : <Menu />}
        </button>
      </div>
      <aside className={`sidebar ${mobile ? "sidebar-open" : ""}`}>
        <Brand />
        <div className="workspace-label">
          <span className="workspace-avatar">
            {(user?.firstName || "P")[0]}
          </span>
          <div>Personal workspace</div>
        </div>
        <nav aria-label="Main navigation">
          {nav.map(({ to, label, icon: Icon }) => (
            <Link
              to={to}
              key={to}
              activeProps={{ className: "nav-item active" }}
              inactiveProps={{ className: "nav-item" }}
              onClick={() => setMobile(false)}
            >
              <Icon size={18} />
              {label}
            </Link>
          ))}
        </nav>
        <div className="sidebar-shortcuts"><WorkspaceShortcuts /></div>
        <div className="sidebar-credits">
          <p>Powered by <a href="https://clickhouse.com/cloud" target="_blank" rel="noreferrer">ClickHouse Cloud</a></p>
        </div>
        <div className="sidebar-account">
          <UserButton />
          <div>
            {user?.fullName || user?.firstName || "Your account"}
            <small>{user?.primaryEmailAddress?.emailAddress}</small>
          </div>
        </div>
      </aside>
      <div className="app-content">
        <main id="main">
          <Outlet />
        </main>
        <footer className="app-footer">
          <span>Shortwave © {new Date().getFullYear()}</span>
        </footer>
      </div>
    </div>
  );
}
