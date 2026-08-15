# Camera Preview (mandavkarpranjal.cam-preview)

A live camera preview bar widget for [Omarchy](https://omarchy.org). The bar
gets a camera icon; clicking it opens a popup with a live preview of your
webcam, a device picker, a mirror toggle, and a snapshot button.

## Features

- Live preview rendered as a fast "slideshow" of still captures (works around
  Qt's FFmpeg camera backend, which neither paints late-mounted VideoOutputs
  nor releases the sensor on `Camera.active = false`)
- Sensor fully released when the popup closes — no `/dev/video0` left open
- Camera device picker (persisted in shell.json), default "Auto"
- Mirror toggle (default on, like a front-facing camera; snapshots are always
  saved unmirrored)
- Snapshot capture: click the bar icon with the right mouse button, or the
  Snapshot button in the popup — saves `~/Pictures/camera-preview-<timestamp>.jpg`
- IPC: `omarchy-shell mandavkarpranjal.cam-preview toggle|takeSnapshot|setMirror <true|false>`

## Requirements

- Omarchy shell (Quickshell-based) with the bar plugin
- A working v4l2 webcam
- A Nerd Font for the icon glyphs (JetBrainsMono Nerd Font ships with Omarchy)

## Installation

The plugin directory name must match the plugin id (`mandavkarpranjal.cam-preview`).

Clone straight into the Omarchy user plugin dir:

```sh
git clone https://github.com/MandavkarPranjal/cam-preview.git ~/.config/omarchy/plugins/mandavkarpranjal.cam-preview
```

Or install with the helper script:

```sh
./install.sh            # copies into ~/.config/omarchy/plugins/mandavkarpranjal.cam-preview
./install.sh --link     # symlinks instead (handy for development)
./install.sh --remove   # removes the installed copy
```

Then restart the shell and enable the widget in the bar:

```sh
omarchy restart shell
```

Add the widget from the Omarchy settings panel (bar layout editor, category
System) or via `omarchy-shell` config tooling.

## Usage

| Action | How |
| --- | --- |
| Open / close preview | Left-click the camera icon in the bar |
| Take a snapshot | Right-click the bar icon, or the Snapshot button |
| Pick a camera | Dropdown in the popup header |
| Mirror / unmirror | Mirror button in the popup header (or `setMirror` IPC) |

Snapshots land in `~/Pictures/camera-preview-*.jpg`.

## Settings

Stored as flat keys on the widget's entry in `~/.config/omarchy/shell.json`
(e.g. `"mirror": true`); editable there or via the settings panel.

| Key | Default | Description |
| --- | --- | --- |
| `device` | `auto` | Camera device id, or `auto` for the system default |
| `previewWidth` | `480` | Preview width in the popup (240-960, 16:9) |
| `mirror` | `true` | Flip the preview horizontally; snapshots unaffected |

## Troubleshooting

- **Stale behavior after editing QML**: the shell hot-reload reuses the old
  compiled component — run `omarchy restart shell` after any change.
- **No camera found**: check `v4l2-ctl --list-devices` and that your user can
  open `/dev/video0` (`video` group / loginctl).
- **FPS**: the sensor self-limits to ~15-30 fps per still capture; that is
  normal for this architecture.

## License

MIT — see [LICENSE](LICENSE).
