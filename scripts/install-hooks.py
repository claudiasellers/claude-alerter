#!/usr/bin/env python3
"""Add Claude Alerter hooks to ~/.claude/settings.json (idempotent; keeps everything else as-is).
Run with --remove to take them out again."""
import json, os, shutil, sys

SETTINGS = os.path.expanduser("~/.claude/settings.json")
BIN = '"$HOME/Applications/ClaudeAlerter.app/Contents/MacOS/ClaudeAlerter"'
EVENTS = ["UserPromptSubmit", "Stop", "Notification", "SessionEnd"]
MARK = "ClaudeAlerter.app"

settings = {}
if os.path.exists(SETTINGS):
    with open(SETTINGS) as f:
        settings = json.load(f)
    shutil.copy(SETTINGS, SETTINGS + ".bak-claude-alerter")

hooks = settings.setdefault("hooks", {})
for event in EVENTS:
    groups = [g for g in hooks.get(event, [])
              if not any(MARK in h.get("command", "") for h in g.get("hooks", []))]
    if "--remove" not in sys.argv:
        groups.append({"hooks": [{
            "type": "command",
            "command": f"{BIN} --hook {event} 2>/dev/null || true",
            "timeout": 5,
        }]})
    if groups:
        hooks[event] = groups
    else:
        hooks.pop(event, None)
if not hooks:
    settings.pop("hooks")

os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
with open(SETTINGS, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(("Removed" if "--remove" in sys.argv else "Installed") + f" Claude Alerter hooks in {SETTINGS}")
