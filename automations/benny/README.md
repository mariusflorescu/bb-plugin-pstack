# benny automations (inactive reference only)

These files are retained verbatim from upstream pstack as reference/template data. They are **not installed, enabled, scheduled, or executed** by this skill library.

- They target a specific external automation product and describe a Cursor-specific layout (`.cursor/automations/benny/`, `.cursor/settings.json`, Cursor cloud agents/automations). Those paths and products are inactive here.
- The `SKILL.md` files under `skills/` here are direct automation instructions for that external system, not registered plugin skills. Do not treat them as active pstack skills.
- `templates/configuration.example.yaml`, `templates/*-automation-prompt.md`, and the `references/*.example.md` files are placeholders. Copy and fill them only if you deliberately set up that external automation, and never store secrets in them in plaintext.
- Setting any of this up requires explicit user authorization, external runtime prerequisites (an available automation service, a model with a public slug, a secret manager), and is outside the scope of loading this library.

If you do not run that external automation product, ignore this directory entirely.
