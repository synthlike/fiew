<!-- agent-workflows-record
{"archived":false,"created":"2026-08-27T19:05:34Z","id":"terminal-compatibility-boundary-for-fiew-v0-2","modified":"2026-08-27T19:05:34Z","record_type":"research","title":"Terminal compatibility boundary for fiew v0.2"}
-->
# Terminal compatibility boundary for fiew v0.2

## Question

Which terminal capabilities and representative terminals provide a defensible cross-platform compatibility target for fiew v0.2?

## Findings

- libvaxis supports macOS, Linux, BSD, Windows, and other Unix-like platforms. It detects terminal features through runtime queries rather than terminfo and exposes the Kitty keyboard protocol, bracketed paste, mouse handling, synchronized output, and related VT capabilities.
- The Kitty keyboard protocol is backward-compatible and opt-in. Its official implementation list includes Ghostty, Kitty, WezTerm, Alacritty, foot, iTerm2, Windows Terminal, and other terminals.
- Ghostty, Kitty, and WezTerm provide a small representative matrix that spans macOS and Linux while sharing the modern keyboard protocol already supported by libvaxis.
- Protocol support does not replace application smoke testing. Startup and restoration, keyboard input, mouse input, resize, Unicode cell rendering, and fallback behavior must be exercised in each required terminal.
- Multiplexers can alter protocol behavior and should not be implied by direct-terminal compatibility. tmux compatibility needs a separate boundary if it becomes required.

## Recommendation

Require Ghostty, Kitty, and WezTerm smoke tests for v0.2 on the supported operating-system targets. Treat other xterm-compatible terminals as best-effort unless promoted by a later compatibility decision. Keep multiplexer support outside the required matrix until tested explicitly.

## Sources

- [libvaxis project documentation](https://github.com/rockorager/libvaxis)
- [Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
- [libvaxis discussion of tmux keyboard-protocol limitations](https://github.com/rockorager/libvaxis/discussions/264)
