import Terminal from "./terminal";
import CopyChip from "./copychip";
import Nav from "./nav";
import Footer from "./footer";
import Motion from "./motion";

const GUIDE_STEPS = [
  ["Open cPanel → SSH Access and generate a new SSH key with a passphrase", "cPanel UI", false],
  ["Set the right key permissions, or the key silently fails", "cPanel UI", false],
  ["Manage SSH Keys → view and copy the public key", "cPanel UI", false],
  ["Download and convert the private key if you ever use PuTTY", "cPanel UI", false],
  ["Open GitHub → repository → Settings → Deploy keys", "GitHub", false],
  ["Paste the public key, save it with the right access level", "GitHub", false],
  ["Copy the SSH clone URL from GitHub's Code button", "GitHub", false],
  ["cPanel → Git Version Control → Create → paste URL, set path and name", "cPanel UI", false],
  ["Confirm github.com's host key when the scary prompt appears", "cPanel UI", false],
  ["Debug it yourself when any step fails — cryptic errors included", "you're on your own", true],
];

const MAPPING = [
  {
    manual: "Generate an SSH key in cPanel → SSH Access, set passphrase and permissions",
    title: "Key created through cPanel's own key system",
    body: "It is generated via cPanel's API (SSH::genkey), so it shows up natively in SSH Access → Manage SSH Keys — with a name you can recognise.",
  },
  {
    manual: "Copy the public key into GitHub → Deploy keys, choose the access level",
    title: "Deploy key added by the GitHub API",
    body: "Read-only, scoped to your one repo. Your token is used for a few seconds and never stored on the server.",
  },
  {
    manual: "Confirm github.com's host key when the trust prompt appears",
    title: "Host key pre-trusted before anything connects",
    body: "Fetched from GitHub's official key list and written to known_hosts, so no scary prompt ever appears — for you or for cPanel.",
  },
  {
    manual: "Copy the clone URL, fill the Create form: path, name, URL",
    title: "Repo cloned to the folder you pick",
    body: "One question, sensible default (~/public_html/your-repo), branch pre-filled from GitHub.",
  },
  {
    manual: "Hope the repo shows up correctly in Git Version Control",
    title: "Registered via cPanel's UAPI, then verified",
    body: "The tool re-lists cPanel's repositories and only reports success when yours is really there.",
  },
  {
    manual: "Decode cryptic SSH errors when something fails",
    title: "Every failure says what to do next",
    body: "Connection is tested at each step, and errors end with the exact command that fixes them.",
  },
];

const STEPS = [
  {
    title: "Check the server",
    body: "git, curl, PHP and cPanel's own command APIs are detected first. No root is used at any point — everything lives in your home folder.",
    api: "git --version · command -v uapi · /usr/local/cpanel/bin/cpapi2",
  },
  {
    title: "Verify your token and the repo — before touching anything",
    body: "A fine-grained GitHub token (Administration: write, Contents: read) is checked against the GitHub API. Wrong token, missing repo or missing permission? You get a plain-language message before any change is made.",
    api: "GET api.github.com/repos/owner/repo",
  },
  {
    title: "Create the SSH deploy key through cPanel",
    body: "The key pair is generated via cPanel's API so it appears in SSH Access → Manage SSH Keys. The public half is added to GitHub as a read-only deploy key, and the SSH login is tested against GitHub.",
    api: "cpapi2 SSH genkey · POST /repos/.../keys · ssh -T git@github.com",
  },
  {
    title: "Pick where the site lives",
    body: "Default is ~/public_html/your-repo. Your branch is pre-filled from GitHub's default branch — just press Enter.",
    api: null,
  },
  {
    title: "Clone the private repo",
    body: "Cloned over SSH with your new key. Your first project gets the standard git@github.com:owner/repo.git remote — nothing tool-specific in the URL.",
    api: null,
  },
  {
    title: "Register it in cPanel → Git Version Control",
    body: "Called through cPanel's own UAPI, then confirmed by re-listing your repositories. The repo now behaves exactly like one you created by hand in the cPanel UI.",
    api: "uapi VersionControl create · uapi VersionControl retrieve",
  },
];

const COMMANDS = [
  ["repo start", "The full setup wizard — keys, clone, registration, verification."],
  ["repo status", "Check the connection right now: SSH to GitHub, sync state, ahead/behind, plain-language results."],
  ["repo deploy", "Publish now — fetch and reset to the latest commit, everything logged."],
  ["repo repair", "Fix a diverged working tree so cPanel's Update from Remote works again."],
  ["repo rollback", "Serve an older commit for a moment — the next deploy returns to latest."],
  ["repo log", "Read the deploy history for this project."],
  ["repo key", "Show the deploy key, re-add it to GitHub, or register it in cPanel's key manager."],
  ["repo register", "(Re)register the repo in cPanel Git Version Control and verify it appears."],
  ["repo uninstall", "Remove what the tool added — asks before touching anything."],
];

const SECURITY = [
  ["Your token is used once, then gone", "It is read with hidden input, used for two API calls, and never written to disk. Delete it on GitHub right after setup — the tool even reminds you to."],
  ["The deploy key can only read one repo", "Read-only, scoped to a single repository. If the server were ever compromised, there is no GitHub token sitting there to steal — just one limited key."],
  ["Keys live where cPanel expects them", "Created through cPanel's own key system inside your home folder. cPanel already blocks public access to .git directories on your account."],
  ["Nothing is deleted without asking", "Every uninstall step confirms first, the riskiest ones confirm twice. Removing the tool never breaks a working site."],
];

const FAQ = [
  ["Do I need root or any special hosting plan?", "No. Everything runs as your cPanel user from cPanel → Terminal. Shared hosting is exactly the target: files live in your home folder, no package installs, no system changes."],
  ["Does my repo really show up in cPanel → Git Version Control?", "Yes — gitship registers it through cPanel's own UAPI (the same thing the Create form does) and then verifies the repo is listed. If your host restricts that API, the tool prints the three fields to enter by hand instead."],
  ["How do updates work after setup?", "Push to GitHub, then click Update from Remote in cPanel → Git Version Control. That's cPanel's native flow. If the button ever refuses because the server tree diverged, run repo repair — then the button works again. repo deploy publishes without the click."],
  ["Is auto-deploy on push included?", "No — gitship is deliberately cPanel-native: no webhooks, no cron jobs, no extra moving parts. The tool's job is to make the hard setup disappear; after that, cPanel manages everything and the tool can be deleted without any effect on your site."],
  ["Can I set up several private repos on one server?", "Yes. GitHub deploy keys are one per repository, so gitship gives each project its own key and its own SSH config entry automatically."],
  ["What if the GitHub token stops working later?", "Nothing breaks — the token is only needed at setup moments. If you revoke it, future setup steps ask for a new one. The ongoing connection uses the deploy key, which stays on GitHub independently."],
];

export default function Page() {
  return (
    <>
      <Nav />
      <Motion />

      <header className="hero" id="top">
        <div className="wrap hero-grid">
          <div>
            <h1>One command puts your private GitHub repo on cPanel.</h1>
            <p className="lede">
              The official cPanel guide walks you through <strong>ten manual steps</strong> across two
              websites — SSH keys, deploy keys, host key prompts, clone forms. <strong>gitship</strong> does
              the entire dance for you from cPanel Terminal, then hands the repo to cPanel&apos;s own Git
              Version Control.
            </p>
            <CopyChip />
            <p className="hero-meta">
              <span>No root.</span> <span>No paid plan.</span> <span>No keys to manage.</span> Works on any
              cPanel shared host with Terminal access.
            </p>
          </div>
          <Terminal />
        </div>
      </header>

      <section className="oldway" id="oldway">
        <div className="wrap" data-reveal>
          <div className="sec-head">
            <h2>The official guide asks a beginner for all of this</h2>
            <p>Every line below is a real step from cPanel&apos;s own Git documentation for private repositories. Each one is a place to get stuck.</p>
          </div>
          <div className="guide-panel">
            <div className="guide-title">
              <span className="dot"></span><span className="dot"></span><span className="dot"></span>
              Guide to Git — private repositories, the manual route
            </div>
            <div className="guide-list">
              <ol>
                {GUIDE_STEPS.map(([txt, cost, miss], i) => (
                  <li key={i} className={miss ? "miss" : ""}>
                    <span className="txt">{txt}</span>
                    <span className="cost">{cost}</span>
                  </li>
                ))}
              </ol>
            </div>
          </div>
          <p className="oldway-note">
            Most of these steps only exist to move one small key from one place to another. That handoff is
            exactly what gitship automates.
          </p>
        </div>
      </section>

      <div className="divider wrap">
        <h2>gitship does <em>the whole dance</em> in one command</h2>
        <p>Same result as the guide — a private repo, fully managed in cPanel → Git Version Control. Ten manual steps become two questions and one paste.</p>
      </div>

      <section id="mapping">
        <div className="wrap" data-reveal>
          <div className="sec-head">
            <h2>Manual step, automated</h2>
            <p>The same private-repo guide, before and after gitship runs. Struck through is what you
              never do by hand again; underneath it is what happens instead.</p>
          </div>
          <div className="fix-panel" aria-label="The cPanel guide's manual steps, each replaced by what gitship does automatically">
            <div className="fix-title">
              <span className="dot"></span><span className="dot"></span><span className="dot"></span>
              Guide to Git — private repositories, now automated
            </div>
            {MAPPING.map((m, i) => (
              <div className="fix-row" key={i}>
                <div className="num">0{i + 1}</div>
                <div>
                  <div className="fix-old">
                    <span className="x">✕</span>
                    <span className="txt">{m.manual}</span>
                  </div>
                  <div className="fix-new">
                    <span className="chk">✓</span>
                    <span>
                      <strong>{m.title}</strong> <span className="body">— {m.body}</span>
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="setup">
        <div className="wrap" data-reveal>
          <div className="sec-head">
            <h2>What <span className="mono">./repo start</span> actually runs</h2>
            <p>Six checks and steps, each one verified before the next begins.</p>
          </div>
          <div className="steps">
            {STEPS.map((s, i) => (
              <div className="step-row" key={i}>
                <div className="n">{i + 1}</div>
                <div className="b">
                  <h3>{s.title}</h3>
                  <p>{s.body}</p>
                  {s.api && <p className="api">{s.api}</p>}
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="after" id="after">
        <div className="wrap" data-reveal>
          <div className="sec-head">
            <h2>After setup, it&apos;s just… cPanel</h2>
            <p>gitship doesn&apos;t replace anything. The repo lands in the Git Version Control page you already know, and publishing stays one click.</p>
          </div>
          <div className="after-grid">
            <div>
              <div className="cp-mock" role="img" aria-label="Illustration of the cPanel Git Version Control manage page showing the repository, branch and the Update from Remote button">
                <div className="cp-top">
                  <span className="logo">cPanel</span>
                  <span style={{ fontWeight: 400, fontSize: "12.5px", opacity: 0.8 }}>Home » Files » Git Version Control</span>
                </div>
                <div className="cp-body">
                  <div className="cp-crumb">Manage » secret-app</div>
                  <div className="cp-row"><span className="k">Repository Name</span><span className="v">secret-app</span></div>
                  <div className="cp-row"><span className="k">Repository Path</span><span className="v">/home/you/public_html/secret-app</span></div>
                  <div className="cp-row"><span className="k">Checked-Out Branch</span><span className="v">main</span></div>
                  <div className="cp-row"><span className="k">Clone URL</span><span className="v">git@github.com:you/secret-app.git</span></div>
                  <div className="cp-row"><span className="k">Last Deployed</span><span className="v">2 minutes ago · a1b2c3d</span></div>
                  <button className="cp-btn" type="button" tabIndex={-1}>
                    Update from Remote
                    <small>pull the latest commit from GitHub — one click</small>
                  </button>
                </div>
              </div>
              <p className="after-fig">Illustration of what you&apos;ll see. The real page is cPanel&apos;s own — gitship only puts your repo on it.</p>
            </div>
            <ul className="after-points">
              <li><strong>Publish with one click</strong>After every <span className="mono">git push</span>, open Git Version Control and press Update from Remote. That&apos;s the whole workflow.</li>
              <li><strong>Or skip the click</strong><span className="mono">repo deploy</span> pulls the same code from Terminal — useful when cPanel&apos;s button refuses, because it pulls with fast-forward only.</li>
              <li><strong>Broken state? One command repairs it</strong>Server edits, failed merges, half-uploads — <span className="mono">repo repair</span> resets the tree so the button works again.</li>
              <li><strong>Delete the tool whenever you like</strong>The repo, the SSH key and cPanel&apos;s management are independent. gitship was only the installer.</li>
            </ul>
          </div>
        </div>
      </section>

      <section id="commands">
        <div className="wrap" data-reveal>
          <div className="sec-head">
            <h2>Commands</h2>
            <p>Installed to <span className="mono">~/bin/repo</span> during setup — works from any folder in cPanel Terminal.</p>
          </div>
          <div className="cmd-table">
            {COMMANDS.map(([c, d], i) => (
              <div className="cmd-row" key={i}>
                <div className="c">{c}</div>
                <div className="d">{d}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="security">
        <div className="wrap" data-reveal>
          <div className="sec-head"><h2>Security, in plain terms</h2></div>
          <div className="sec-grid">
            {SECURITY.map(([h, p], i) => (
              <div className="sec-item" key={i}>
                <h3>{h}</h3>
                <p>{p}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="faq">
        <div className="wrap" data-reveal>
          <div className="sec-head"><h2>Questions beginners actually ask</h2></div>
          {FAQ.map(([q, a], i) => (
            <details key={i} open={i === 0}>
              <summary>{q}</summary>
              <p>{a}</p>
            </details>
          ))}
        </div>
      </section>

      <div className="cta">
        <div className="wrap" data-reveal>
          <h2>Your private repo is one command away</h2>
          <p>Run this in cPanel → Terminal, answer two questions, paste a temporary token.</p>
          <CopyChip />
        </div>
      </div>

      <Footer />
    </>
  );
}
