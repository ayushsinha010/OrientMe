"use client";

import { usePathname } from "next/navigation";
import { AuthProvider, PUBLIC_PATHS, useAuth } from "../lib/AuthContext";
import Sidebar from "./Sidebar";
import CommandPalette from "./CommandPalette";

function Guarded({ children }) {
  const { user, loading } = useAuth();
  const pathname = usePathname();

  // Public auth pages render standalone - no sidebar/search chrome for a
  // logged-out person to see. Everything else is the admin console and
  // needs a real session.
  if (PUBLIC_PATHS.has(pathname)) return children;

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen text-slate-400 text-sm">
        Loading…
      </div>
    );
  }

  // Not logged in - AuthProvider's own effect is already redirecting to
  // /login; render nothing in the meantime rather than flashing real data.
  if (!user) return null;

  return (
    <div className="flex min-h-full">
      <CommandPalette />
      <Sidebar />
      <main
        className="flex-1 min-w-0 bg-cream"
        style={{
          // Soft decorative glow in the bottom-left corner (pure CSS, no image).
          backgroundImage:
            "radial-gradient(circle at 12% 88%, rgba(0, 166, 192, 0.07) 0%, rgba(122, 46, 158, 0.04) 28%, rgba(253, 251, 244, 0) 55%)",
          backgroundRepeat: "no-repeat",
          backgroundAttachment: "fixed",
        }}
      >
        {children}
      </main>
    </div>
  );
}

export default function AppShell({ children }) {
  return (
    <AuthProvider>
      <Guarded>{children}</Guarded>
    </AuthProvider>
  );
}
