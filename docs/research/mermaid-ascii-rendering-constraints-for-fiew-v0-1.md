<!-- agent-workflows-record
{"archived":false,"created":"2026-08-25T21:29:32Z","id":"mermaid-ascii-rendering-constraints-for-fiew-v0-1","modified":"2026-08-25T21:29:32Z","record_type":"research","title":"Mermaid ASCII rendering constraints for fiew v0.1"}
-->
# Mermaid ASCII rendering constraints for fiew v0.1

## Question

Which dependency and rendering boundary can display useful Mermaid diagrams as terminal-native text without expanding fiew into a browser or image viewer?

This research informs ISSUE-0011.

## Verified findings

- Official Mermaid CLI accepts Mermaid definitions and produces SVG, PNG, or PDF output. Its normal installation uses the Node ecosystem and its rendering environment involves Puppeteer/Chromium.
- The Kitty graphics protocol transports images to a supporting terminal; it does not parse or render Mermaid source. Using it for Mermaid would still require an SVG/PNG renderer.
- The selected libvaxis revision advertises Kitty graphics support, so image display is technically available but not sufficient by itself.
- `mermaid-ascii` is a separate MIT-licensed Go project that parses a Mermaid subset and renders Unicode terminal text or strict ASCII.
- `mermaid-ascii` release 1.5.0 resolves to commit `b1b35f67d6a5dd0699ccfc968c00a763db573076` and publishes a `Darwin_arm64` archive.
- The tool reads input from stdin when no file is provided or when `--file -` is used.
- Its documented supported diagram types are graphs/flowcharts, sequence diagrams, and entity-relationship diagrams. It does not implement the full Mermaid language.
- Its CLI exposes fixed box and inter-node spacing controls plus an ASCII-mode flag. It does not expose a target viewport width or general responsive-layout option.
- Neither `mmdc` nor `mermaid-ascii` is installed in the local environment.

## Interpretation

- `mermaid-ascii` fits fiew's text-first interaction better than raster output: its result can pass through fiew's ordinary cell renderer, selection, scrolling, and sanitization boundaries.
- A user-installed executable avoids adding Go, Node, Chromium, SVG parsing, image lifetime, and Kitty image-placement dependencies to fiew.
- Fixed compact spacing and horizontal scrolling are more predictable than rerendering on terminal resize because the renderer cannot target a width.
- Since the executable receives diagram source as data on stdin and does not evaluate repository build files, repository trust is not required. Normal subprocess containment and output sanitization remain necessary.

## Remaining uncertainty

- Startup latency, output quality, exit behavior, and exact error messages have not been verified locally because the executable is absent.
- Patch releases after 1.5.0 are policy-compatible within the selected 1.5 line but unverified.
- The accepted one-second execution limit and source/output size caps are conservative product policies, not measured renderer limits.
- Mermaid subset compatibility may differ from official Mermaid parsing for syntax that `mermaid-ascii` only partially implements.

## Sources

- [Mermaid CLI repository](https://github.com/mermaid-js/mermaid-cli)
- [Mermaid CLI 11.16.0 release](https://github.com/mermaid-js/mermaid-cli/releases/tag/11.16.0)
- [Mermaid security-level documentation](https://mermaid.js.org/config/usage.html#securitylevel)
- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/)
- [Selected libvaxis README](https://github.com/rockorager/libvaxis/blob/c060d314930c5552b99a89278a6a695baf0352da/README.md)
- [mermaid-ascii repository](https://github.com/AlexanderGrooff/mermaid-ascii)
- [mermaid-ascii 1.5.0 release](https://github.com/AlexanderGrooff/mermaid-ascii/releases/tag/1.5.0)
- [mermaid-ascii 1.5.0 CLI source](https://github.com/AlexanderGrooff/mermaid-ascii/blob/1.5.0/cmd/root.go)
