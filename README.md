# PolishPop 0.4.1

PolishPop is a personal macOS menu-bar app that polishes selected text through the official Codex App Server and ChatGPT-managed OAuth.

## What it does

- Shows a sparkle button after you select editable text.
- Polishes the selection with a Professional, Natural, Friendly, Concise, or Executive tone.
- Replaces the original selection in place when the target app supports it.
- Provides `⌥⌘P` as a global keyboard shortcut.
- Signs in through the official Codex-managed ChatGPT OAuth browser flow.
- Uses the Codex allowance or credits included with an eligible ChatGPT plan—no OpenAI API key or separate API billing.
- Rejects secure/protected fields and revalidates the exact app, field, range, and text before replacement.

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

## Install

1. Unzip `PolishPop-0.4.1.zip`.
2. Move `PolishPop.app` to `/Applications`.
3. Open it. Because this personal MVP is ad-hoc signed rather than notarized, macOS may require Control-click → **Open** the first time.
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

Version 0.4.1 is **not ready for Mac App Store submission**. It remains a direct-download MVP for two architectural reasons:

1. Apple requires Mac App Store apps to enable App Sandbox, while Apple documents the use of Accessibility APIs in assistive apps as incompatible with App Sandbox: <https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox>
2. Mac App Store apps must be self-contained. This MVP depends on a separately installed, OpenAI-signed Codex CLI. Apple’s review guidelines require apps to be appropriately sandboxed, packaged through Xcode, and submitted as a single self-contained bundle: <https://developer.apple.com/app-store/review/guidelines/>

An App Store edition therefore needs a different interaction model, such as an `NSServices`/Share-extension workflow where the host app explicitly hands selected text to PolishPop, plus a bundled and licensed inference/OAuth component. That edition would not be able to display the current universal floating button through Accessibility.

## Build from source

```sh
./scripts/package_app.sh
```

The packaging script:

1. builds the Swift 6 release executable;
2. runs seven deterministic protocol/prompt checks;
3. performs a live local Codex app-server initialization/account smoke test without opening OAuth;
4. creates and ad-hoc signs `PolishPop.app`;
5. archives the app as `PolishPop-0.4.1.zip`.

The package contains no third-party Swift dependencies and never embeds an API key or OAuth token.
