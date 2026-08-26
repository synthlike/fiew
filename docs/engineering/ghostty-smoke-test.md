# Ghostty smoke test

Use this checklist for terminal behavior that deterministic tests cannot verify.

## Prerequisites

- Apple Silicon macOS
- Ghostty
- Zig 0.16.0
- Dependencies fetched with `zig build --fetch`

## Checks

1. Run `zig build run -- /path/to/repository` in Ghostty.
2. Confirm Project displays a directory tree and moving with `j`/`k` previews files without moving focus.
3. Press `Enter` on a file. Confirm the preview is pinned and the main view gains focus.
4. Use `h`/`j`/`k`/`l` in the main view. Confirm the selected grapheme and byte range move without entering source-editing behavior.
5. Press `v` and move to extend the selection. Confirm `;`, `Alt-;`, and `Esc` collapse, reverse, and leave Extend mode as documented.
6. Press `Tab` and `Shift-Tab`, then click and drag in Project and the main view. Confirm focus and the contiguous selection are visually explicit.
7. Collapse and expand a directory with `h`/`l`. Press `Esc` during a preview and `Space b` to collapse Project. Confirm the last pinned file and exact location are restored.
8. Open multiple files, then use `Ctrl-o` and `Ctrl-i`. Confirm backward and forward location history restores each file and selection.
9. Open `Space`, `Space ?`, and `:`. Confirm menus and help list disabled commands with reasons, invalid sequences report feedback, `q` closes help without quitting, and `:quit` is available.
10. Resize across 100 columns. Confirm Project changes between beside and overlay layouts without losing selection or scroll position. Below 60×20, confirm the unsupported-size message appears.
11. Open a binary file and confirm only metadata appears. If available, open a file containing invalid UTF-8 and confirm replacement characters appear without changing the file.
12. Use `Space q`. Confirm fiew exits, the previous terminal contents return, the cursor is visible, and normal line input and echo work.
13. Run fiew again and press `Ctrl-C`. Confirm the same restoration behavior.

## Result

Record the date, Ghostty version, macOS version, and any failed step in the implementation issue.
