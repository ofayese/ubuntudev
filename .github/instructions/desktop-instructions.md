---
applyTo: "**/*.sh"
---

# Native Ubuntu Desktop Guidelines

## Package Management

- Use `apt` for system packages, prefer `snap` for applications
- Check for package availability before installation
- Implement proper dependency chains

## Desktop Integration

- Install VS Code locally: `snap install code --classic`
- Create `.desktop` entries for custom applications
- Use `xdg-open` for file associations
- Integrate with desktop notifications via `notify-send`

## Environment Setup

```bash
# Desktop environment detection
is_desktop_environment() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
}

# Check for specific desktop environments
is_gnome() { [ "${XDG_CURRENT_DESKTOP:-}" = "GNOME" ]; }
is_kde() { [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; }
```

## System Services

- Use systemd for service management
- Configure user services in `~/.config/systemd/user/`
- Handle both X11 and Wayland compatibility
