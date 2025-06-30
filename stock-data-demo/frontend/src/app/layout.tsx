import type { Metadata } from "next";
import { Inter } from "next/font/google";
import Script from "next/script";
import "./globals.css";
// import dynamic from "next/dynamic";
// const Home = dynamic(() => import("@/pages/home"), { ssr: false });

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "StockHouse",
  description: "ClickHouse Stock Data Demo App",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head>
        <Script src="/stocks/crypto-polyfill.js" strategy="beforeInteractive" />
      </head>
      <body>
        <main>{children}</main>
      </body>
    </html>
  );
}
