import { Sora, Public_Sans, JetBrains_Mono } from "next/font/google";
import "./globals.css";

const sora = Sora({ subsets: ["latin"], weight: ["600", "700", "800"], variable: "--font-sora", display: "swap" });
const pub = Public_Sans({ subsets: ["latin"], weight: ["400", "600"], variable: "--font-public", display: "swap" });
const mono = JetBrains_Mono({ subsets: ["latin"], weight: ["400", "600"], variable: "--font-mono", display: "swap" });

export const metadata = {
  title: "gitship — one command sets up your private GitHub repo on cPanel",
  description:
    "gitship automates every manual step from the cPanel guide: SSH keys, GitHub deploy keys, host key trust, cloning and Git Version Control registration — one command, no root, 100% cPanel native.",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body className={`${sora.variable} ${pub.variable} ${mono.variable}`}>{children}</body>
    </html>
  );
}
