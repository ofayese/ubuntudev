# Global Copilot Instructions

- Prefer modular bash scripts: `check-prerequisites.sh`, `env-detect.sh`, etc.
- Respect WSL2 vs native Ubuntu paths; do not assume `sudo` where unnecessary.
- Maintain headless compatibility (CLI) separate from desktop.
- Use consistent shebangs (e.g., `#!/usr/bin/env bash`) and adhere to POSIX.
- Include ample comments and `set -eux` for failsafe behavior.
