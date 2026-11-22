"use client";

import { useEffect, useState } from "react";
import GhIcon from "./ghicon";

const LINKS = [
  ["oldway", "The old way"],
  ["mapping", "What gitship does"],
  ["setup", "Setup"],
  ["after", "After setup"],
  ["commands", "Commands"],
  ["faq", "FAQ"],
];

export default function Nav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState("");

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  // scroll-spy: highlight the section currently on screen
  useEffect(() => {
    const obs = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) setActive(e.target.id);
        });
      },
      { rootMargin: "-35% 0px -60% 0px" }
    );
    LINKS.forEach(([id]) => {
      const el = document.getElementById(id);
      if (el) obs.observe(el);
    });
    return () => obs.disconnect();
  }, []);

  return (
    <nav className={scrolled ? "scrolled" : ""}>
      <div className="nav-in">
        <a className="brand" href="#top" onClick={() => setOpen(false)}>
          <span className="mark">&gt;_</span>gitship
          <span className="ver">v2.0.0</span>
        </a>
        <div className={"nav-links" + (open ? " open" : "")}>
          {LINKS.map(([id, label]) => (
            <a
              key={id}
              href={"#" + id}
              className={active === id ? "active" : ""}
              onClick={() => setOpen(false)}
            >
              {label}
            </a>
          ))}
          <a className="gh" href="https://github.com/rezwanvaiya2-0/gitship" target="_blank" rel="noopener">
            <GhIcon />
            <span>GitHub</span>
          </a>
        </div>
        <button
          type="button"
          className={"burger" + (open ? " open" : "")}
          aria-expanded={open}
          aria-label="Toggle menu"
          onClick={() => setOpen(!open)}
        >
          <i></i><i></i><i></i>
        </button>
      </div>
    </nav>
  );
}
