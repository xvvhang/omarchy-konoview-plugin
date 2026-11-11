# Validation record

Checked 2026-11-11 for the findings on marketplace issue #14592:

- Replaced native clipboard transfer with SafeSearch interception before Qt
  handling (Ctrl+V/Shift+Insert/Paste key, custom right-click menu and middle
  primary paste). Worker reads at most 4096 bytes with a 1-second absolute
  deadline; completion requires unchanged panel/focus/edit/caret/selection/IME
  revision. Closing/reopening and focus loss cancel/invalidate the operation.
- Extracted the dynamic unavailable-preview caption into FallbackCaption with
  PlainText and a 256-character sanitized class limit. An actual local HTTP
  observer saw zero image requests from the production caption while the
  RichText positive control requested its image.
- All finite Hyprland queries now use worker.py and BoundedProcess: bounded
  reply, deadline, producer kill/reap, helper watchdog, cancellation and reset.
  Fixed a JavaScript `arguments` shadowing bug by using `root.arguments`.
- Native Quickshell fixture tests exercise correct argument delivery, helper
  timeout, cancellation, failure, failed-start and retry. Producer fixtures
  exercise slow/continuous/oversized/stalled output, EOF-without-exit, missing
  command/nonzero exit, process reaping and retry. They do not replace the
  user's clipboard or constitute live malicious Wayland-owner testing.
- Only normalized metadata reaches the GUI: 1 MiB raw producer cap, 128 recent
  windows, bounded fields and valid sizes/addresses. Captures have a 12-source
  count budget plus estimated per-source/aggregate pixel admission limits.
  Cache, selection, close/reload owner checks remain intact.
- Eight Python tests (including native Quickshell fixtures and HTTP observer),
  nine offscreen QtTest results, four Node suites, manifest validation and
  diff checks passed. Qt lint has the existing theme/delegate-resolution
  warnings; no errors in the new components.
- Live overview opened with seven windows and correct rounding after helper
  fix. Final marketplace validation and maintainer review remain outstanding.

Checked 2026-11-10 for zero-size mapping/recreated captures:

- Added `captureTiming` IPC to count preview construction and time source
  assignment separately from first content. Six windows created 12 previews.
- Temporary layout tracing isolated a 0-width, -140-height initial viewport:
  it chose one column, then switched to three at 1368x760 after configure.
- Use target-screen geometry until the viewport is valid; row array identity
  now depends on window membership and column count, not every geometry change.
- After the fix, four samples created exactly six previews each, with first
  content at 150/121/116/137 ms and source-to-content at 122/110/106/114 ms.
- Remaining source-to-content time is not yet attributed to a specific native
  capture stage. No capture-resolution reduction was applied: the installed
  Quickshell 0.3.2 API exposes display constraints, not a capture-size request.

Checked 2026-11-10 for prioritized capture startup:

- Upstream ScreencopyView creates a capture on source assignment; constraintSize
  affects implicit size only. Hyprland capture requests ignore damage on the
  first frame, so waiting for window damage is not an established explanation.
- Four parallel-capture samples reported first content at 228/208/213/196 ms.
  Focused-window-only samples were 204 ms cold, then 142/142/138 ms.
- Start the focused (or first filtered) preview before the remaining captures.
  After its first content, start the rest 16 ms later; a 250 ms fallback prevents
  an unavailable priority window from blocking other captures. Close stops timers.
- Four prioritized samples reported 152/144/176/156 ms first content and 5–7 ms
  cached-image readiness; all six thumbnails were cached by the sample endpoint.
  These are readiness timings, not screen-presentation measurements.
- Delaying thumbnail grabs by 500 ms did not reliably reduce first-frame timing
  and left short visits uncached; that experiment was reverted.

Checked 2026-11-10 for second-press activation:

- Corrected the press bindings from `SUPER + SUPER_L/R` to standalone
  `Super_L/R` (runtime modifier mask 0). Kept working release bindings at mask 64.
- After reload/restart, live status recorded `pressCount: 9`, `opened: true`
  and `lastTapInterval: 75`, confirming physical press events reached the plugin.
- Added non-consuming press bindings alongside the existing lone-release
  bindings. First release arms; second press toggles; its release is suppressed.
- `node tests/gesture.cjs` covers second-press activation, duplicate-release
  suppression, timeout, legacy release-only bindings and missing-release recovery.
- Live IPC `tap`, `press`, `status`, `tap`, `status` confirmed opening on press
  without re-toggling on release. Physical keyboard behavior needs user testing.
- Hyprland reload/config validation and the layout/model tests passed.
- A chord beginning with Super inside an armed interval necessarily triggers on
  press before the remaining chord keys are known; this is the timing tradeoff.

Checked 2026-11-10 for layer creation timing:

- Four open-command samples first observed the layer via `hyprctl layers -j`
  at 42.5–46.9 ms, including command launch and polling overhead.
- `status.startup.layerVisibleMs` records Qt backing-window visibility, not
  compositor presentation; samples were 1–3 ms after entering open.
- Deferring capture by 16 ms did not measurably improve layer discovery
  (42.8–49.5 ms) and was reverted rather than adding capture delay.
- Physical bindings still trigger on the second Super release, not press.

Checked 2026-11-10 for cached thumbnail fallback:

- Grab preview thumbnails into memory when live content arrives and before
  closing. Retain grab results for their image URLs; never write them to disk.
- Cache keys include window address and PID. Prune missing windows on list
  refresh, cap retention at 64 images and thumbnail dimensions at 640px.
- In three open/close samples, the second and third opens had cached images
  ready at 7 ms and 6 ms; live capture became ready at 211 ms and 194 ms.
  These are content-ready measurements, not compositor presentation latency.
- First open still requires live capture. Cached images yield immediately to
  live content; failed/missing grabs fall back to the original placeholder.
- Tests cover cache pruning, memory bounds and stale asynchronous callbacks.
- Visual transitions, disabled animations and rapid reopen need manual testing.

Checked 2026-11-10 for startup profiling and fast IPC:

- Seven status calls had a median of 86.7 ms with `IpcHandler`, versus 19.6 ms
  with `ShellIpc`. Existing double-Super command bindings were not changed.
- Three baseline open calls took 110–120 ms; fast IPC open calls took 38–49 ms.
- `status.startup` records synchronous open/model work and time until the first
  ScreencopyView reports content. It does not measure screen presentation.
- First preview content remained approximately 180–285 ms after entering open;
  JSON/model updates took 0–9 ms. Capture readiness remains the main bottleneck.
- Retaining hidden preview objects did not improve capture readiness and was
  removed. Duplicate unchanged model updates are skipped to avoid recaptures.
- `node tests/populate.cjs`, `node tests/layout.cjs`, and `git diff --check` pass.
- Physical double-Super responsiveness and visual smoothness need user testing.

Checked 2026-10-29 for plugin-owned compositor blur:

- Removed the external layer rule from `~/.config/hypr/hyprland.lua`.
- Manifest validation and `git diff --check` passed. Qt 6 qmllint reported
  existing delegate-scope/theme warnings, none in the new lifecycle code.
- Restarted the shell to update the keepLoaded service; the runtime
  `konochi-konoview-blur` rule reported enabled through `hyprctl repl`.
- After `hyprctl reload`, the plugin restored the enabled rule and
  `hyprctl configerrors` was empty.
- Live disable/unload cleanup and visual blur still need manual verification.

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
