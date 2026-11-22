"use client";

import { useState } from "react";

const CMD =
  "git clone https://github.com/rezwanvaiya2-0/gitship.git && cd gitship && ./repo start";

export default function CopyChip() {
  const [copied, setCopied] = useState(false);

  function copy() {
    const done = () => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(CMD).then(done).catch(done);
    } else {
      const ta = document.createElement("textarea");
      ta.value = CMD;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
      done();
    }
  }

  return (
    <div className="chip">
      <span>{CMD}</span>
      <button type="button" onClick={copy} className={copied ? "copied" : ""}>
        {copied ? "Copied" : "Copy"}
      </button>
    </div>
  );
}
