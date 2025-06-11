# Copilot Workflow Automation

## Goal

Standardize how Copilot is used in your repo with reusable prompts and consistent practices.

## Steps

1. Configure `.vscode/settings.json` or JetBrains/Neovim configs.
2. Add `.github/prompts/` and `.github/instructions/` for shared AI prompts.
3. Create `README-copilot.md` to explain usage conventions.

## Best Practices

- Use `/prompt` in Copilot Chat to activate reusable workflows.
- Maintain prompt history and edits inside `.github/prompts/`.
- Separate WSL2 vs Desktop logic in `.github/instructions/`.

> Reuse these conventions across multiple repositories.
