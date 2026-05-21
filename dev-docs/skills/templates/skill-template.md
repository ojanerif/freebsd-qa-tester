# Skill Template

Copy this to `dev-docs/skills/skills.jsonl` as a single JSON object (one line).

```json
{
  "id": "skill-id",
  "name": "Human-readable skill name",
  "category": "development | testing | debugging | database | deployment | security | documentation | legal",
  "summary": "One sentence description of what this skill does.",
  "triggers": ["keyword1", "keyword2", "intent phrase"],
  "owner": "user_id",
  "status": "draft | active | deprecated | archived",
  "confidence": "high | medium | low",
  "last_verified": "YYYY-MM-DD",
  "commands": ["command1", "command2"],
  "files": ["path/to/file"],
  "outputs": ["Expected output or result"],
  "risks": ["Risk description if destructive"],
  "prompt": "Instruction block for AI agent when applying this skill."
}
```

## Rules

- Start as `"status": "draft"` when uncertain — Owner promotes to `"active"`.
- `confidence: low` means the skill needs human verification before use.
- Destructive skills **must** include `risks` with confirmation wording.
- `triggers` are matched by AI agents against user intent — be specific.
- `prompt` is the instruction the AI agent reads when using this skill.
