# Codex Dream Skin

An unofficial, reversible Windows theme layer for the Store-installed ChatGPT/Codex desktop app. It injects visual styling through a loopback-only Chromium DevTools Protocol session and does **not** modify `WindowsApps`, `app.asar`, app signatures, chat history, projects, or login data.

## Open-source edition

This repository is the publishable source edition. It includes:

- PowerShell runtime, injector, CSS, tests, and maintenance documentation.
- Windows manager / installer / uninstaller source code.
- A neutral, original abstract demo background.

## Upstream attribution

This is an independently maintained derivative of [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin), which is published under the MIT License. The derivative keeps the required attribution and license terms while adding a Windows-oriented manager, compatibility diagnostics, safety checks, and a neutral demonstration theme. It is not an official upstream release or a replacement for it. See [UPSTREAM.md](UPSTREAM.md).

It intentionally excludes:

- Character artwork, user-imported themes, previews, and personal assets.
- Node.js and official application binaries.
- Logs, profiles, user settings, chats, projects, credentials, release `.exe` files, and archives.

## Requirements

- Windows 10/11.
- The Microsoft Store edition of ChatGPT/Codex installed for the current user.
- Node.js 22 or later available on `PATH` (this repository does not redistribute it).
- PowerShell 5.1 or later.

## Quick start for contributors

1. Clone the repository.
2. Review `dream-skin/README.md` and `dream-skin/MAINTENANCE_PLAYBOOK.md`.
3. From the repository root, run the engine tests:

```powershell
node .\dream-skin\tests\renderer-inject.test.mjs
node .\dream-skin\tests\injector-bootstrap.test.mjs
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\dream-skin\tests\run-tests.ps1
```

4. Install only after closing the desktop app and reviewing the scripts. The live runtime stores its own state under `%LOCALAPPDATA%\CodexDreamSkin`; this folder is excluded from Git.

## Security and compatibility

- The debugging endpoint is bound to `127.0.0.1` only. Treat a running debug session as sensitive and do not run untrusted local programs beside it.
- Do not broaden CSS into layout rules. The theme layer is visual only; official elements retain their own size, position, grid, flex, and interaction behavior.
- Do not use generated class hashes or translated UI text as primary selectors. Follow the compatibility baseline and maintenance playbook.
- ChatGPT/Codex updates can alter renderer markers. Diagnose identity, injection, route state, CSS, lifecycle, and distribution in that order before changing a selector.

## License

MIT. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
