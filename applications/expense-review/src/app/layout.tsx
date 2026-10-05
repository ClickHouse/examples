import "./globals.css";
export const metadata = {
  title: "Expense review workbench",
  description: "Review the exact saved claim revision.",
};
export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
