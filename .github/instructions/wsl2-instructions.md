---
applyTo: "**/*.sh"
---
When running under WSL2:

- Use Linux-style `\n` line endings (skip Windows conversion).
- Prioritize using `/mnt/c/...` paths and avoid GUIs.
- Ensure scripts detect and handle WSL via `uname -r`.
