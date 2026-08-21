# PolishPop 0.5.0

PolishPop is a personal macOS menu-bar app that polishes selected text through the official Codex App Server and ChatGPT-managed OAuth.

## What it does

- Shows a sparkle button beside the text you just selected.
- Polishes the selection with a Professional, Natural, Friendly, Concise, or Executive tone.
- Opens a review panel that highlights, word by word, exactly what the rewrite changed.
- Replaces the original selection in place when the target app supports it.
- Offers a configurable shortcut (`⌥⌘P` by default) and an optional instant-replace shortcut with undo.
- Speaks English and 简体中文, following the system language by default.
- Signs in through the official Codex-managed ChatGPT OAuth browser flow.
- Uses the Codex allowance or credits included with an eligible ChatGPT plan—no OpenAI API key or separate API billing.
- Rejects secure/protected fields and revalidates the exact app, field, range, and text before replacement.

## What is new in 0.5.0

This release is a usability pass over the whole app.

**Nothing interrupts you.** Errors used to be modal alerts that activated PolishPop and pulled focus
out of whatever you were typing in — a stray `⌥⌘P` with no selection was enough to do it. Every
routine message is now a small non-activating toast beside your cursor, with a relevant action button
(Open Settings, Undo) where one helps.

**The wait is visible and interruptible.** The review panel now opens the moment you click the
sparkle, showing your original with the draft still being written, plus **Stop**. Previously you
watched a 38-point spinner with no way to cancel and a 90-second ceiling.

**You can see what changed.** The panel diffs the original against the draft and highlights
insertions in the draft and deletions in the original, word by word for Latin text and character by
character for Chinese. Character and word deltas are shown alongside.

**Keyboard-complete.** `⌘↩` replaces, `⇧⌘C` copies, `⌘R` regenerates, `⎋` cancels, `⌘.` stops
generation. `Return` inserts a paragraph break instead of firing Replace. A real Edit menu makes
`⌘C`/`⌘V`/`⌘X`/`⌘A`/`⌘Z` work inside the draft editor, which they previously did not.

**It stops working when you are not.** The sparkle button is anchored to the selection rectangle
rather than the mouse pointer, disappears when you switch to another application, and auto-hides
after 15 seconds instead of floating over every Space until your next click.

**It costs far less while idle.** The selection monitor used to make a blocking, cross-process
Accessibility query on the main thread after *every* left-click and every Shift keystroke anywhere on
the system, with up to 2 seconds of worst-case messaging timeouts. It now runs those queries on a
background queue and only after a gesture that can actually create a selection — a drag, a
double-click, Shift-navigation, or `⌘A`.

**Instant replace, with a way back.** Turn on the optional instant-replace shortcut to skip the review
panel entirely. PolishPop keeps your original wording and offers **Undo** in the toast and in the
menu-bar menu, which reselects what it wrote and puts your words back.

**Settings apply immediately.** The Save button is gone — changes take effect as you make them.
The model is now a menu of what your plan actually offers rather than a free-text field where a typo
silently fell back to a different model. Shortcuts are recordable, Accessibility permission is
detected while you grant it without relaunching, and there are Launch at Login, Hide Dock Icon and
language options.

**Direct replacement is tried first.** Apply previously always went through the clipboard. It now
attempts a verified direct Accessibility write and only falls back to a temporary paste when the
target application refuses or silently ignores it — and that paste is now confirmed to have landed
before your clipboard is restored, instead of after a fixed 500 ms guess.

## Important account boundary

PolishPop acts as a small Codex client. It uses Codex App Server authentication and Codex models covered by your eligible ChatGPT plan’s Codex allowance or credits.

It does **not** access:

- custom GPTs
- ChatGPT conversations or projects
- ChatGPT history or memory
- ordinary OpenAI API credits

The connection uses a dedicated `CODEX_HOME` under PolishPop’s Application Support folder, isolating its configuration and ephemeral session state from the normal Codex CLI home. OAuth tokens are owned, stored, and refreshed by Codex; PolishPop never reads them. The credential store is forced to the macOS keyring, whose entry namespace remains controlled by Codex.

## Requirements

- Apple Silicon Mac running macOS 13 or later
- Codex CLI 0.147.0 or later installed at a standard Homebrew/npm location
- An eligible ChatGPT account with Codex access and remaining usage

The version packaged here was built and smoke-tested against `codex-cli 0.147.0`.

## Download

<https://polishpop.eric-c85.workers.dev>

The download page carries the same installation and privacy notes as this file, in English and
Simplified Chinese, along with the SHA-256 of the archive so it can be checked before opening.

The site is a static Cloudflare Worker; its source is in `site/`, and `wrangler deploy` from that
directory publishes it. `site/public/PolishPop-*.zip` is deliberately git-ignored — copy the archive
that `scripts/package_app.sh` produces into `site/public/` before deploying, and update the version
number and checksum in `site/public/index.html` to match.

## Install

1. Unzip `PolishPop-0.5.0.zip`.
2. Move `PolishPop.app` to `/Applications`.
3. Open it. This build is signed with a self-issued certificate but is **not notarized**, so macOS
   blocks the first launch with *"PolishPop" Not Opened* and offers only **Move to Trash** and
   **Done**. Click Done.

   Control-click → Open no longer works: Apple removed that override in macOS 15 Sequoia
   (<https://developer.apple.com/news/?id=saqachfa>). The documented replacement is to attempt the
   launch, then go to System Settings → Privacy & Security → Security and click **Open Anyway**
   within about an hour. macOS may not offer that row for a self-signed app at all, in which case
   remove the quarantine mark yourself:

   ```sh
   xattr -dr com.apple.quarantine /Applications/PolishPop.app
   ```

   That skips Gatekeeper's whole first-launch assessment for this app, so verify the archive
   against its published SHA-256 first. Installing with `curl` avoids the situation entirely,
   because curl does not mark its downloads as quarantined — note that `unzip` *does* propagate
   quarantine from an already-quarantined archive, so it is the download tool that matters, not the
   unzip step.
4. Click **Sign in with ChatGPT** and complete the OpenAI browser authorization.
5. Grant Accessibility permission when prompted.

PolishPop shows a normal Dock icon and standard application menu. Quit it from **PolishPop → Quit PolishPop**, the Dock icon’s menu, `⌘Q`, or the **Quit PolishPop** button in Settings.

Signing out from PolishPop calls Codex’s official logout endpoint and does not sign the browser out of ChatGPT. Because the macOS keyring namespace is controlled by Codex, verify your other Codex clients afterward if you use the same ChatGPT account in several local clients.

### If you previously saw `persist_failed`

Version 0.2.0 incorrectly gave the Codex child process an app-private `HOME`, which prevented macOS from locating the default login keychain. Version 0.2.1 and later restore the real user home for Keychain Services while keeping `CODEX_HOME`, configuration, runtime files, and the subprocess environment isolated. Install the latest version and retry **Sign in with ChatGPT**; no manual keychain deletion is required.

## Use

1. Select editable text in Mail, Notes, a browser, Feishu/Lark, or another app.
2. Click the sparkle button, or press `⌥⌘P`.
3. PolishPop sends only that selection to OpenAI through Codex and opens a non-activating floating review panel on the same active Desktop/Space where you clicked the sparkle. The source app stays in front and macOS does not switch to PolishPop’s Home Desktop.
4. Compare the original with the editable polished draft.
5. Optionally choose **Smart / Auto**, **Email**, **Chat message**, **Social post / 朋友圈**, **Business update**, or **Announcement**; choose a tone; then click **Regenerate** to refresh the draft in the same panel.
6. Choose **Apply to Original**, **Copy Draft**, or **Cancel**. The source content is never changed before you explicitly apply the draft.

If direct replacement is unavailable, the polished result remains available under the menu-bar command **Copy Last Polished Text**.

When direct Accessibility replacement is unavailable, clicking **Apply to Original** automatically uses a temporary paste fallback and then restores the previous clipboard. Clipboard-history utilities may briefly observe that temporary draft.

## Privacy and safety

- Text is transmitted only after an explicit sparkle click or keyboard shortcut.
- Every rewrite uses a fresh ephemeral Codex thread.
- PolishPop uses an isolated, empty working directory, a read-only/no-network sandbox, `approvalPolicy: never`, and instructions forbidding tools.
- If Codex attempts to start a tool, file change, command, MCP call, web search, or other non-text action, PolishPop interrupts and rejects the rewrite.
- Codex transcript history is disabled and each thread is ephemeral. PolishPop does not add selections to its own storage; the last result expires from memory after five minutes. Codex may still maintain operational/security metadata under its applicable data controls.
- ChatGPT/Codex data controls, retention rules, plan limits, and usage policies still apply.
- Never select passwords, banking details, private keys, confidential contracts, medical information, or sensitive employee records.

## Compatibility

Selection support is best-effort because some applications—particularly canvas-based web editors, PDFs, protected fields, and custom text controls—do not expose selected text through macOS Accessibility.

This MVP is directly distributed and not App-Sandboxed because system-wide Accessibility automation is incompatible with a conventional Mac App Store sandbox.

## Logo and app-icon assets

The source includes:

- `Support/PolishPopIcon-1024.png` — opaque 1024×1024 master artwork
- `Support/AppIcon.iconset/` — macOS PNG representations from 16×16 through 512×512@2x
- `Support/PolishPop.icns` — icon embedded in the direct-download app
- `Assets.xcassets/AppIcon.appiconset/` — Xcode macOS AppIcon asset catalog

The icon is original PolishPop artwork and intentionally contains no Apple, OpenAI, ChatGPT, or Codex marks.

## Mac App Store status

Version 0.5.0 **cannot** be submitted to the Mac App Store, and no amount of configuration changes
that. App Sandbox is mandatory there — Guideline 2.4.5(i), verbatim: "They must be appropriately
sandboxed" — and two of this app's mechanics are impossible inside a sandbox.

Both blockers were confirmed by A/B experiment on macOS 26.5.2: one binary, two bundles differing
only by `com.apple.security.app-sandbox`.

1. **Reading and writing another app's selected text.** Sandboxed *and* granted Accessibility
   trust, every cross-process `AXUIElementCopyAttributeValue` returned `kAXErrorCannotComplete`
   (−25204); the unsandboxed control returned 0 against the same apps. The sandboxed build fails
   with a *different* error than an untrusted build (−25211 `kAXErrorAPIDisabled`), i.e. it is
   refused at the sandbox layer before the TCC gate, so granting permission cannot help. Apple's
   own list of activities "forbidden by the operating system when an app runs in a sandbox"
   includes "Use of accessibility APIs in assistive apps":
   <https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox>
   There is no entitlement for it — neither the 30 App Sandbox keys nor the 11 temporary-exception
   keys contain anything for the Accessibility API — and the temporary-exception mechanism now
   directs developers to file feature requests instead.

2. **Running the separately installed Codex CLI.** A sandboxed bundle could not read or execute
   `/opt/homebrew/bin/codex` (`NSCocoaErrorDomain` Code=4); the unsandboxed control ran it fine.
   Guideline 2.5.2 is explicit without needing any inference: apps "may not download, install, or
   execute code which introduces or changes features or functionality of the app, including other
   apps." Embedding the CLI does not rescue it either: Apple's helper-tool workflow re-signs
   embedded executables with the submitting team's identity, which would invalidate the OpenAI
   signature check in `CodexAppServerClient.verifyCodexExecutable`.

What is **not** a blocker, contrary to the obvious guess:

- Global `NSEvent` mouse monitoring works sandboxed, untrusted (measured: 77 events in six seconds
  versus 128 for the control).
- Global key monitoring works sandboxed once Accessibility trust is granted.
- Posting synthetic `CGEvent` keystrokes works sandboxed with that same trust.
- Carbon `RegisterEventHotKey` returns `noErr` sandboxed.
- The business model is fine. Guideline 3.1.1 obliges in-app purchase only for unlocking features
  for money, and this app sells nothing; a free client for the user's own third-party paid account
  has shipping precedent on the Mac App Store.

So an App Store edition would have to be a **different, reduced product**: text handed over
explicitly through `NSServices` (verified to work inside the sandbox) rather than lifted out of the
frontmost app, and the model called directly over HTTPS under
`com.apple.security.network.client` rather than through an external CLI. That second change also
ends the property this app is built around — that it runs on the Codex allowance of the user's own
ChatGPT plan and never holds a key — because the developer would then own the API relationship and
the bill.

The realistic path for *this* product is Developer ID plus notarization, which is also what
OpenAI's own ChatGPT Mac app does for the same reason. Note the current packaging is not yet
notarization-ready: `scripts/package_app.sh` signs with neither `--options runtime` nor a secure
timestamp, and the self-issued certificate is rejected by the notary service outright.

## Stable code signing

`scripts/package_app.sh` signs with a local certificate named **PolishPop Self-Signed** when one is
present in the login keychain, and falls back to ad-hoc signing with a warning when it is not.

This matters for permissions rather than for distribution. An ad-hoc signature's designated
requirement is the code hash:

```
designated => cdhash H"d898c5bc..."
```

That hash changes on every build, so macOS treats each build as a different application and discards
the Accessibility permission — the stale entry stays visible in System Settings but no longer
matches, and toggling it off and on does not help; it has to be removed and re-added. Signing with a
certificate produces a requirement that survives rebuilds:

```
designated => identifier "com.demry.polishpop" and certificate leaf = H"1c68d4b2..."
```

Accessibility is then granted once and keeps working across builds.

To create the certificate on a new machine, either use Keychain Access → Certificate Assistant →
Create a Certificate (name it `PolishPop Self-Signed`, identity type Self Signed Root, certificate
type Code Signing), or from the command line:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout key.pem -out cert.pem \
  -subj "/CN=PolishPop Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -in cert.pem -inkey key.pem -name "PolishPop Self-Signed" -out polishpop.p12 -passout pass:TRANSIENT
security import polishpop.p12 -k ~/Library/Keychains/login.keychain-db -P TRANSIENT -T /usr/bin/codesign
rm -f key.pem polishpop.p12   # the private key now lives in the keychain
```

`security find-identity -v -p codesigning` will still report zero valid identities, because a
self-signed certificate is untrusted for *verification*. That does not prevent *signing*, and the
designated requirement it produces is what PolishPop needs. This is not a substitute for a Developer
ID certificate and notarization; Gatekeeper still treats the app as unidentified.

## Install from source

```sh
git clone https://github.com/demry-max/PolishPop.git
cd PolishPop
./scripts/install.sh
```

This builds the release binary, runs the checks that work without an account, assembles and signs
the bundle, and installs it to `/Applications`. Set `POLISHPOP_DEST` to install somewhere else.

It is worth preferring over the download for one concrete reason: macOS applies the quarantine flag
to files a browser downloaded, not to software you compiled yourself, so an app installed this way
never produces the *"PolishPop" Not Opened — Apple could not verify…* dialog and needs none of the
System Settings ceremony described above.

Do not use `scripts/package_app.sh` for this. That one is the release script and runs live Codex
smoke tests, which need an account that is already signed in — impossible before the app exists.

## Build from source

```sh
./scripts/package_app.sh
```

The packaging script:

1. builds the Swift 6 release executable;
2. runs 106 deterministic checks covering the Codex protocol, prompts, the diff engine, text
   statistics, shortcut encoding, and translation completeness;
3. renders every screen in both languages to PNG for visual inspection;
4. performs a live local Codex app-server initialization/account smoke test without opening OAuth;
5. creates and ad-hoc signs `PolishPop.app`;
6. archives the app as `PolishPop-0.5.0.zip`.

Two development-only modes help review the interface without a Codex account:

```sh
./.build/release/PolishPop --render-ui /tmp/polishpop-ui   # every screen, both languages, as PNG
./.build/release/PolishPop --window-probe                  # reports the frames macOS gives the panels
```

Two more exist for support:

```sh
/Applications/PolishPop.app/Contents/MacOS/PolishPop --diagnose
open -a /Applications/PolishPop.app --args --debug-log   # then read ~/Library/Application Support/PolishPop/debug.log
```

`--diagnose` prints permission, shortcut, and Codex-CLI state. Note that macOS attributes
Accessibility permission to the process *responsible* for the launch, so running it from a terminal
that itself holds Accessibility permission reports a false positive; `--debug-log` is authoritative
because the app must be started by LaunchServices for the flag to reach it. The debug log records
whether a selection was seen and how long it was, never its contents.

`--render-ui` draws into offscreen windows, so it needs no Screen Recording permission and never
flashes anything on the display. `--window-probe` exists because offscreen rendering cannot catch a
window that AppKit sizes differently from the view it contains.

The package contains no third-party Swift dependencies and never embeds an API key or OAuth token.
