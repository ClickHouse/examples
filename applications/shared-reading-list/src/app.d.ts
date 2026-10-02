import type { auth } from "$lib/server/auth";
declare global {
  namespace App {
    interface Locals {
      user?: typeof auth.$Infer.Session.user;
    }
  }
}
export {};
