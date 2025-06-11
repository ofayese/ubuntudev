---
applyTo: "**/*.sh"
---

# WSL2-Specific Development Guidelines

## Environment Detection

```bash
# Detect WSL2 environment
is_wsl2() {
    [ -f /proc/version ] && grep -qi microsoft /proc/version
}

# Check systemd availability
is_systemd_running() {
    [ -d /run/systemd/system ] && systemctl is-system-running >/dev/null 2>&1
}
```

## File System Handling

- Use Linux-style `\n` line endings (skip Windows conversion)
- Prioritize `/mnt/c/...` paths when accessing Windows files
- Use `wslpath` for path conversion: `wslpath -w /path/to/file`
- Avoid case-sensitive operations on Windows drives

## Integration Points

- Windows VS Code: `/mnt/c/Program Files/Microsoft VS Code/bin/code.cmd`
- Git credential integration: `git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"`
- Windows hostname: `cmd.exe /c "hostname"` for consistency

## Performance Optimization

- Configure .wslconfig for memory/CPU limits
- Use wsl.conf for mount options and boot settings
- Prefer native Linux tools over Windows equivalents when possible

## Desktop Applications

- Avoid GUI applications in scripts; rely on Windows host
- Use Windows clipboard via `clip.exe` for text output
- Launch Windows applications with `cmd.exe /c start`
