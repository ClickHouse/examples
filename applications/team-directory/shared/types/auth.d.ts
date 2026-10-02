declare module "#auth-utils" {
  interface User {
    id: string;
  }
  interface UserSession {
    loggedInAt?: string;
  }
}
export {};
