"use client";

import { useEffect } from "react";

// adds .reveal-hide to [data-reveal] elements, then swaps to .reveal-in as
// they scroll into view; reduced-motion users see everything immediately
export default function Motion() {
  useEffect(() => {
    const els = Array.from(document.querySelectorAll("[data-reveal]"));
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) return;
    els.forEach((el) => el.classList.add("reveal-hide"));
    const obs = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            e.target.classList.add("reveal-in");
            obs.unobserve(e.target);
          }
        });
      },
      { threshold: 0.1 }
    );
    els.forEach((el) => obs.observe(el));
    return () => obs.disconnect();
  }, []);
  return null;
}
