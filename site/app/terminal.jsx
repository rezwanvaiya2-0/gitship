"use client";

import { useEffect, useState } from "react";

const CMD_LINE = "./repo start";
const LINES = [
  ["step", "== 1/6  Checking your server (as your cPanel user — no root) =="],
  ["ok", "[ok] git: git version 2.36.1"],
  ["ok", "[ok] cPanel uapi: found — automatic Git Version Control registration"],
  ["ok", "[ok] cPanel cpapi2: found — key will be created through cPanel"],
  ["step", "== 2/6  Your private repository =="],
  ["q", "? Private repo URL: git@github.com:you/secret-app.git"],
  ["q", "? Paste the GitHub token  (input hidden)"],
  ["ok", "[ok] Token verified - repository reachable, default branch: main"],
  ["step", "== 3/6  SSH deploy key (automatic) =="],
  ["ok", "[ok] SSH key created through cPanel: ~/.ssh/cpanel_deploy_secret-app"],
  ["ok", "[ok] Deploy key added to GitHub (read-only, this repo only)"],
  ["ok", "[ok] github.com host key pre-trusted (no interactive prompts)"],
  ["ok", "[ok] GitHub accepts this key: Hi you! You've successfully authenticated"],
  ["step", "== 4/6  Where should the site files live? =="],
  ["q", "? Full path: ~/public_html/secret-app"],
  ["step", "== 5/6  Cloning your private repository =="],
  ["ok", "[ok] Cloned to: /home/you/public_html/secret-app"],
  ["step", "== 6/6  Registering with cPanel -> Git Version Control =="],
  ["ok", "[ok] Registered AND verified - it appears in Git Version Control"],
  ["hint", "You can DELETE the GitHub token now - it was never saved on this server."],
];

function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
}

function line(pair) {
  return `<span class="${pair[0]}">${esc(pair[1])}</span>`;
}

export default function Terminal() {
  const [typed, setTyped] = useState("");
  const [shown, setShown] = useState(0);
  const [phase, setPhase] = useState("typing"); // typing -> output -> done

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) {
      setTyped(CMD_LINE);
      setShown(LINES.length);
      setPhase("done");
      return;
    }
    let i = 0;
    const t = setInterval(() => {
      i += 1;
      setTyped(CMD_LINE.slice(0, i));
      if (i >= CMD_LINE.length) {
        clearInterval(t);
        setPhase("output");
      }
    }, 75);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    if (phase !== "output") return;
    let j = 0;
    const r = setInterval(() => {
      j += 1;
      setShown(j);
      if (j >= LINES.length) {
        clearInterval(r);
        setPhase("done");
      }
    }, 170);
    return () => clearInterval(r);
  }, [phase]);

  return (
    <div className="term" aria-label="Example of repo start output">
      <div className="term-bar">
        <i></i><i></i><i></i>
        <span className="t">cpanel-terminal — repo start</span>
      </div>
      <div className="term-body" id="term-body">
        <div>
          <span className="cmd">{typed}</span>
          {phase === "typing" && <span className="caret"></span>}
        </div>
        {LINES.slice(0, shown).map((pair, idx) => (
          <div key={idx} dangerouslySetInnerHTML={{ __html: line(pair) }} />
        ))}
      </div>
    </div>
  );
}
