# Konoview

Part of **Konochi**, a personal Omarchy plugin series by Alec Xu.

An Omarchy shell service, implemented entirely in the user plugin directory.

## Usage

- Double-tap either Super key within 350 ms to toggle the fullscreen overview.
- All mapped Hyprland windows, across all monitors and workspaces (including
  special workspaces and hidden group members), appear in one flat grid.
- Press the letter on a window or click it to close the overview and focus it.
  The compositor switches workspace/monitor as needed; windows are not moved.
- Enter focuses search; typing filters titles, application names, and workspace
  names live (case-insensitive, all whitespace-separated terms must match).
- Esc or Enter in search returns to window-hint mode, keeping the current filter and
  original hint labels. Esc outside search closes without selecting.
  Backspace outside search clears the last hint character.
- More than 26 windows use equally sized, unique multi-letter hints. Hints
  are stable during one opening, sorted by workspace and window address.
- Window cards use a responsive grid; scroll when the content exceeds
  the display. The overview opens on the focused monitor and covers its bar.
- The previously focused window has an accent border. Below each preview,
  its title is on the left and its workspace name and keyboard hint on the right.
- While search is focused, letter keys edit the query instead of selecting windows.
- The background uses the same theme-aware `Color.menu.scrim` as Super+K:
  a translucent solid-color dimmer, with no blur or desktop capture.
  The plugin animates its own scrim
  and content opacity (100 ms in / 80 ms out), retaining previews until fade-out
  finishes. No Hyprland fade animation setting is required.

Uses Quickshell's native ScreencopyView and Hyprland toplevel export. Previews
are live while open and released on close. No screenshots are saved to disk.
Unavailable previews show a labelled fallback; the window can still be selected.
The window list is a snapshot on opening: reopen to include newly created windows.

## Integration

`~/.config/hypr/bindings.lua` registers non-consuming lone Super release bindings
using the shell IPC command (the native global-shortcut release path is not used).
The shell service detects the double tap and prefetches the window list on the
first tap. Existing Super chords are not replaced. `~/.config/hypr/hyprland.lua`
contains the existing `overview-glass` layer rule with compositor blur and
animations disabled; the scrim and fade live in QML.
The bindings are deliberately not enabled while the screen is locked.
`input.resolve_binds_by_sym = true` makes symbol bindings follow each keyboard's
actual XKB mapping, including Alt/Super swaps, instead of the shared translation
keymap. No physical Alt keys or keyboard device names are bound by this plugin.

IPC:

```sh
omarchy-shell konochi.konoview toggle
omarchy-shell konochi.konoview open
omarchy-shell konochi.konoview close
omarchy-shell konochi.konoview status
```

Disable: `omarchy plugin disable konochi.konoview`, and remove the two overview
bindings from `~/.config/hypr/bindings.lua`. The pre-install bindings backup
is named `bindings.lua.bak.overview.<timestamp>`.

## Install and remove

Requires Omarchy Quattro, Hyprland with the `hl.dsp` Lua dispatch interface,
`hyprctl`, and Quickshell's Hyprland toplevel-export/screencopy support.
There is no installer, network access, privileged command, or separate service.

```sh
omarchy plugin add https://github.com/xvvhang/omarchy-konoview-plugin --enable
omarchy-shell konochi.konoview toggle
```

The IPC command works without additional bindings. For the optional double-Super
shortcut, manually add these lines to `~/.config/hypr/bindings.lua` after checking
for conflicting bindings and backing up the file:

```lua
o.bind("SUPER + SUPER_L", "Konoview (double-tap Super)", "omarchy-shell konochi.konoview tap", { release = true, non_consuming = true })
o.bind("SUPER + SUPER_R", "Konoview (double-tap Super)", "omarchy-shell konochi.konoview tap", { release = true, non_consuming = true })
```

Validate changes with `hyprctl reload` and `hyprctl configerrors`. Local compositor
settings described in Integration are not installed automatically and are not
required for IPC use. Existing backups and bindings are specific to each machine.

To uninstall, remove only the bindings you added, then:

```sh
omarchy plugin disable konochi.konoview
omarchy plugin remove konochi.konoview
```

No window images are retained. Back up unpushed changes before removal.

## Validation

```sh
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell ./*.qml
```

Use Qt 6's qmllint (the default executable may be Qt 5). MIT licensed; see LICENSE.
