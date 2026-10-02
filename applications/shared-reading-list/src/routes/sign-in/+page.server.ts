export function load() {
  return { signupEnabled: process.env.SIGNUP_ENABLED === "true" };
}
