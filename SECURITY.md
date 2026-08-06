# Security scope

## What the code may change

The runtime operates only in its managed user-data root:

`%LOCALAPPDATA%\CodexDreamSkin`

It may create or update its own theme copies, state files, logs, a loopback-only CDP session, and user-selected shortcuts. Its cleanup routines validate that a deletion target is inside this managed root before removing it.

## What the code must not change

- `WindowsApps`, `app.asar`, signed application binaries, or application packages.
- Windows Registry, services, drivers, security-policy settings, or firewall rules.
- ChatGPT/Codex account data, chats, tasks, projects, plugins, or official profile files.
- Any network listener other than a local `127.0.0.1` debugging endpoint for the themed session.

## Review guidance

- Treat the local Chromium debugging port as sensitive while it is running.
- Review PowerShell changes for every write or removal operation; managed-root validation is mandatory.
- Do not add code that takes ownership of package directories, disables endpoint protection, or changes execution policy beyond a user-invoked process.
- Test with a non-production profile before releasing a compatibility update.

## Content-safety review before release

Before publishing any release, scan text, metadata, examples, and images for personal information, credentials, political or social advocacy, real-world political messaging, public-figure commentary, and other sensitive social content. Include [CONTENT_NOTICE.md](CONTENT_NOTICE.md) in every release. Release notes and other explanatory text must state that they are AI-generated or AI-edited and do not represent personal opinions.
