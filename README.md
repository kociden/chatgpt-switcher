# ChatGPT Switcher for Windows

Switch between multiple **ChatGPT desktop app** accounts on Windows — like Google's account switcher. Pick an account from a small window and it opens in its own isolated ChatGPT window. Run several accounts side by side.

A single, dependency‑free PowerShell script. **No installer, no background service, ~35 KB, fully auditable.** Your existing login stays untouched as "Main".

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)

> [日本語 README はこちら / Japanese README](README.ja.md)

---

## Why this exists

As of 2026, the official ChatGPT **web** app can switch between up to 2 accounts, but the **desktop app** (the new Microsoft Store app, package `OpenAI.Codex`) has no account switching at all — you have to log out and back in every time.

This script gives the desktop app what Google-style account switching would look like: one click per account, each with its own login, all from a tiny picker.

## Features

- **Account picker** — a small window (like Google's account chooser) to launch any account
- **Full isolation** — each account gets its own Electron user-data dir and `CODEX_HOME`, so logins never collide
- **Run several at once** — open Work and Personal side by side in separate windows
- **Per-account desktop shortcuts** — auto-created, so you can launch straight from the desktop
- **Tray mode** — sit in the system tray; left-click for the picker, right-click to launch any account
- **Your current login is preserved** — it shows up as "Main"; nothing is migrated or overwritten
- **No install, no dependencies** — one PowerShell script + a `.cmd` launcher. Nothing runs in the background unless you choose tray mode.

## Two modes

Each account is one of two modes:

- **Isolated (default)** — its own Electron data and `CODEX_HOME`. Fully separate login and Codex projects/chats. **Multiple accounts can run at once.**
- **Full-share (`-Shared`)** — uses your real `~/.codex`, so **projects, chats and config are shared across accounts** (like the official experience). Only `auth.json` is swapped on switch. **One shared account at a time** (two processes on one `~/.codex` would corrupt it, and current Codex Desktop rejects a symlinked session store). `auth.json` is backed up on every switch; a bad swap is recoverable by re-login.

First run of a shared account: launch it, log in, then run `-SaveAuth <id>` (or right-click it → save current login).

## How it works

The ChatGPT desktop app is an Electron app. Electron honors two things that let you run fully separate instances:

| What | How it's set | Contains |
|------|--------------|----------|
| Electron user data | env `CODEX_ELECTRON_USER_DATA_PATH` + arg `--user-data-dir=` | Cookies (= your ChatGPT login), local settings, cache |
| Codex home | env `CODEX_HOME` | `auth.json`, sessions, config |

Each account is just a folder under `%USERPROFILE%\ChatGPT-Accounts\<id>\` holding its own `electron` and `codex` directories. The script launches `ChatGPT.exe` pointed at those. That's the whole trick — the same approach the macOS tools [ccheney/chatgpt-multi-account](https://github.com/ccheney/chatgpt-multi-account) and [Ducksss/codex-profiles](https://github.com/Ducksss/codex-profiles) use.

## Requirements

- Windows 10 / 11
- The official **ChatGPT desktop app** installed ([Microsoft Store](https://apps.microsoft.com/) or `winget install --id 9PLM9XGG6VKS -s msstore`)
- Windows PowerShell 5.1 (built in) or PowerShell 7+

## Install

### Option A — one-liner (recommended)

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/__OWNER__/__REPO__/main/install.ps1 | iex
```

This downloads the script to `Documents\ChatGPT-Switcher`, and creates a Start Menu + Desktop shortcut. Nothing is installed system-wide.

### Option B — manual

1. Download this repo (green **Code** button → Download ZIP), or clone it.
2. Put the `ChatGPT-Switcher` folder somewhere you like (e.g. `Documents\ChatGPT-Switcher`).
3. Double-click `ChatGPT-Switcher.cmd`.

No execution-policy change is needed — the launcher runs with `-ExecutionPolicy Bypass` for that one process only.

## Usage

Double-click **`ChatGPT-Switcher.cmd`** → choose **日本語 (Japanese)** or **English** → the picker opens.

The last language choice is preselected at the next interactive startup. Closing the language selector cancels startup. Change the language from **Settings → Language** in the picker. The selection applies to the switcher's windows, dialogs, menus, tray, and diagnostics; ChatGPT has its own language settings.

Command-line operations use the saved language without prompting. Pass `-Language en` or `-Language ja` to override it for one invocation and skip the startup selector, for example:

```powershell
ChatGPT-Switcher.cmd -Language en
ChatGPT-Switcher.cmd -Diagnose -Language en
ChatGPT-Switcher.cmd -Tray -Language en
```

Translations are embedded in the script, so the single-file distribution and installer need no additional files. Shortcut filenames stay unchanged when switching languages.

1. Click **＋ Add account**, type a name (Work / Personal / …).
2. A fresh ChatGPT window opens on the sign-in screen — log in with that account.
3. From then on, just click the account in the picker. A desktop shortcut `ChatGPT - <name>` is created too.

Right-click an account in the picker for **shortcut / rename / delete**. Your current login is always there as **Main**.

### Command line

```
ChatGPT-Switcher.cmd                  Open the picker
ChatGPT-Switcher.cmd -Launch Work     Launch a specific account (front if already open)
ChatGPT-Switcher.cmd -Add Work        Add an account (+ desktop shortcut)
ChatGPT-Switcher.cmd -Remove Work     Remove it (deletes this PC's login/cache for it)
ChatGPT-Switcher.cmd -List            List accounts
ChatGPT-Switcher.cmd -Setup           Create picker shortcuts (Desktop + Start Menu)
ChatGPT-Switcher.cmd -Tray            Run in the system tray
ChatGPT-Switcher.cmd -AutoStartTray   Start tray mode at Windows login
ChatGPT-Switcher.cmd -Diagnose        Environment diagnostics
ChatGPT-Switcher.cmd -Version         Print version
```

## Notes & limitations

- The **server-side** history, memory, and billing stay separate per account — this only separates the local session. Nothing is shared or merged.
- All ChatGPT windows share the same taskbar icon. Tell them apart by the avatar in the app's bottom-left, or by the "● running" mark in the picker.
- If a future app update changes the internals, launching may break. Run `-Diagnose` and open an issue with the output.
- Having multiple ChatGPT accounts is not prohibited by OpenAI's terms, but on **Team/Enterprise managed** workspaces, follow your admin's policy.
- This is an **unofficial** tool, not affiliated with or endorsed by OpenAI. Use at your own risk (see [LICENSE](LICENSE)).

## Uninstall

Delete the `ChatGPT-Switcher` folder, the shortcuts, and (optionally) `%USERPROFILE%\ChatGPT-Accounts`. That's everything.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). This is a small, single-file tool by design; the goal is to stay simple and auditable.

## License

[MIT](LICENSE)
