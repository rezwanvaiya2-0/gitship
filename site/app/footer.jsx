import GhIcon from "./ghicon";

export default function Footer() {
  return (
    <footer>
      <div className="wrap foot-grid">
        <div className="foot-brand">
          <a className="brand" href="#top">
            <span className="mark">&gt;_</span>gitship
          </a>
          <p>
            One command sets up private GitHub repos on cPanel shared hosting. Then cPanel manages
            everything, the way it always has.
          </p>
        </div>
        <div className="foot-col">
          <h4>Explore</h4>
          <a href="#oldway">The old way</a>
          <a href="#mapping">What gitship automates</a>
          <a href="#setup">How setup works</a>
          <a href="#after">After setup</a>
          <a href="#commands">Commands</a>
        </div>
        <div className="foot-col">
          <h4>On GitHub</h4>
          <a href="https://github.com/rezwanvaiya2-0/gitship" target="_blank" rel="noopener">
            <GhIcon size={14} /> Repository
          </a>
          <a href="https://github.com/rezwanvaiya2-0/gitship/blob/main/README.md" target="_blank" rel="noopener">
            <GhIcon size={14} /> README
          </a>
          <a href="https://github.com/rezwanvaiya2-0/gitship/issues" target="_blank" rel="noopener">
            <GhIcon size={14} /> Report an issue
          </a>
        </div>
      </div>
      <div className="wrap foot-bottom">
        <span>© 2026 gitship. Works on any cPanel shared host with Terminal access.</span>
        <span>Made for people who just want to ship.</span>
      </div>
    </footer>
  );
}
