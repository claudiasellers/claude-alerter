# Claude Alerter

A small Mac menu bar utility that tells you which Claude threads are **done** and waiting for you,
so you don't have to click through every chat to find out.

- **Menu bar:** `✦ 2` means two threads are ready. Click it to see them.
- **Desktop card (optional):** a frosted card pinned to your wallpaper on every Space. You can drag it anywhere.
- **Click a thread** to jump straight to it: desktop sessions open in the Claude app, terminal sessions bring
  their terminal or editor to the front. Clicking also marks the thread seen. Hover and click ✓ to mark it seen without opening it.

Sections: **Ready for you** (finished or needs your input, not seen yet), **Working**, **Seen**.

## What it tracks

| Where you use Claude | How it's detected |
|---|---|
| Claude desktop app → **Code** tab | Reads the app's local session files. No setup needed. |
| Claude Code in a terminal / editor | Claude Code hooks (one-time install below) |
| Regular claude.ai chats / Cowork | Not yet: their state isn't stored on your Mac |

## Install

```bash
./build.sh install                 # builds, copies to ~/Applications, launches
python3 scripts/install-hooks.py   # terminal Claude Code support (backs up settings first)
```

Undo the hooks with `python3 scripts/install-hooks.py --remove`.

Data lives in `~/Library/Application Support/ClaudeAlerter/`.
