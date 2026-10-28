# Validation record

Checked 2026-10-28 for selection feedback (supersedes direct workspace selection):

- Manifest validation passed and live shell IPC status responded after reload.
- Qt 6 qmllint completed with delegate-scope/theme-resolution warnings.
- Node assertions passed for selecting the first filtered workspace window,
  scratchpad selection, keeping the overview open during highlighting, ignoring
  duplicate selections, Escape cancellation, and empty-workspace fallback.
- Selection highlights for 120 ms before closing; visual timing and actual
  compositor focus still need manual verification.

Checked 2026-10-28 for workspace shortcuts and reserved S hints:

- Plugin manifest validation passed; shell IPC status responded after hot reload.
- Qt 6 qmllint completed with warnings in existing grid delegates (unqualified
  access and theme property resolution), none in the new shortcut code.
- Node assertions against the QML functions passed: unique, equal-length hints
  without S for 1, 25, 26, 625, 626, and 15626 windows; workspace commands for
  1, 9, 0 (10), and S (scratchpad); deferred window focus remains unchanged.
- Keyboard-handler assertions passed for digits, S, ordinary window hints, and
  bypassing shortcuts while search is focused.
- Physical double-Super and compositor workspace switching still need manual
  verification; automated checks did not change the active workspace.

Checked 2026-10-19 on Omarchy 4.0.5-1, Qt 6.12.0.

- Manifest validation and Qt 6 qmllint: passed for all QML files.
- Running shell: enabled; IPC open/status/close succeeded.
- Open overview reported four windows and four matching windows.
- No standalone automated unit-test suite is present.

Full manual hint selection, search, double-Super, multi-monitor behavior,
restart, and destructive uninstall testing remain to be performed before
requesting marketplace approval. Optional bindings are documented, not installed.
