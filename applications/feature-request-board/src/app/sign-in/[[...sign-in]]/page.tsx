import { SignIn } from "@clerk/nextjs";
export default function SignInPage() {
  return (
    <div className="auth-page">
      <SignIn fallbackRedirectUrl="/" />
    </div>
  );
}
