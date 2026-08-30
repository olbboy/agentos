# Security Policy

## Threat model (summary)

AgeOS manages third-party skill content and rewrites agent client configs — the two obvious attack surfaces. Design stance:

1. **Skills are data, never code.** Scan/score/dedupe/budget only read bytes. AgeOS never executes scripts inside skills, never renders skill content into a shell, and a regression test (booby-trap script that would drop a marker file if executed) guards this.
2. **Client configs are user property.** AgeOS parse-merges its own entry and touches nothing else; broken files are refused (not "fixed"); every write is preceded by a timestamped backup under `~/.ageos/backups/` with a restore command (`ageos mcp restore-backup`).
3. **Only remove what we created.** Double bookkeeping — lockfile entry + `dev.ageos.managed` xattr / `.ageos-manifest.json` — before any delete. Name collisions with user files abort the operation.
4. **MCP health checks spawn the *server the user added*, on purpose,** with timeout, SIGTERM→SIGKILL escalation and no orphan processes (test-verified). Health never runs anything found inside skill content.
5. **Secrets:** MCP env values are stored plaintext in client configs at MVP — identical to what the clients themselves do — and are flagged `sensitive` in the lockfile. macOS Keychain storage is the v1.1 milestone. Never commit configs containing secrets.
6. **Network:** GitHub API/tarballs, registry.modelcontextprotocol.io, and skills.sh only. No telemetry. Embeddings and classification run on-device (NaturalLanguage / FoundationModels).

## Supported versions

Pre-1.0: only the latest release receives fixes.

## Reporting a vulnerability

Open a GitHub Security Advisory (preferred) or email the maintainer. Please include reproduction steps. You should get a response within 7 days.
