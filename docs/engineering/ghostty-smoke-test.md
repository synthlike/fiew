# Ghostty smoke test

Use this checklist for terminal behavior that deterministic unit tests cannot verify.

## Prerequisites

- Apple Silicon macOS
- Ghostty
- Zig 0.16.0
- Dependencies fetched with `zig build --fetch`

## Checks

1. Run `zig build run` in Ghostty.
2. Confirm the alternate screen displays:
   - `fiew`;
   - `read-first code and diff viewer`; and
   - `Press q or Ctrl-C to quit`.
3. Resize the terminal in both dimensions. Confirm the content is cleared and centered again without stale cells.
4. Press `q`. Confirm fiew exits, the previous terminal contents return, the cursor is visible, and normal line input and echo work.
5. Run fiew again and press `Ctrl-C`. Confirm the same restoration behavior.

## Result

Record the date, Ghostty version, macOS version, and any failed step in the implementation issue.
