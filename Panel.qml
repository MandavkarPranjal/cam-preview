import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Live camera preview bar widget. The bar icon is a camera glyph that lights
// up while the preview is streaming; clicking it opens a popup with a live
// preview feed, a camera picker, and a snapshot button.
//
// Why the preview is a "slideshow" of still captures rather than a
// VideoOutput feed:
//
//  1. Qt's FFmpeg camera backend keeps the v4l2 device open (and streaming)
//     after `Camera.active = false`; only destroying the Camera object
//     releases the sensor. So the whole capture stack must be mounted and
//     destroyed with the popup, via a Loader.
//  2. But a VideoOutput never renders frames when it is created after the
//     shell started (the popup window is unmapped at startup and remounted
//     per open) — the sink receives frames, the scene graph node never
//     paints. Verified against a plain Quickshell PanelWindow in all
//     combinations (loader-mount, hidden window, split camera).
//  3. The camera -> ImageCapture pipeline, by contrast, is pure data: a
//     CaptureSession mounted in a Loader captures real JPEGs reliably. The
//     popup then just displays them in a plain Image item, which always
//     renders. Polling a still capture every 30 ms yields ~15-30 fps (the
//     sensor self-limits), with the sensor fully released on close.
Panel {
  id: root
  moduleName: "mandavkarpranjal.cam-preview"
  ipcTarget: "mandavkarpranjal.cam-preview"

  // IPC surface: the base open/close lifecycle plus snapshot control, so
  // `omarchy-shell mandavkarpranjal.cam-preview takeSnapshot` works from outside.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function takeSnapshot(): void { root.takeSnapshot() }
    function setMirror(enabled: string): string {
      var value = String(enabled || "true") === "false" ? false : true
      root.persistSetting("mirror", value)
      return String(root.mirrored)
    }
  }

  // ---------------------------------------------------------------- devices
  // Quickshell does not expose the MediaDevices singleton, but an instance
  // enumerates and tracks the system cameras just as well.
  MediaDevices {
    id: mediaDevices
  }

  readonly property var devices: mediaDevices ? mediaDevices.videoInputs : []
  readonly property bool hasDevices: !!devices && devices.length > 0

  readonly property string requestedDeviceId: String(root.setting("device", "auto") || "auto")
  // Mirror the preview like a mirror (the default for a front-facing camera).
  // Snapshots are always saved unmirrored.
  readonly property bool mirrored: root.setting("mirror", true) !== false

  readonly property var selectedDevice: {
    if (!root.hasDevices) return null
    if (root.requestedDeviceId !== "auto") {
      for (var i = 0; i < root.devices.length; i++) {
        if (String(root.devices[i].id) === root.requestedDeviceId) return root.devices[i]
      }
    }
    return mediaDevices.defaultVideoInput
  }

  readonly property var deviceOptions: {
    var list = [{ value: "auto", label: "Auto (system default)" }]
    for (var i = 0; i < root.devices.length; i++) {
      var d = root.devices[i]
      var suffix = d.isDefault ? " (default)" : ""
      list.push({ value: String(d.id), label: String(d.description) + suffix })
    }
    return list
  }

  // ---------------------------------------------------------------- sizing
  readonly property int previewWidth: Math.max(240, Math.min(960, Number(root.setting("previewWidth", 480)) || 480))
  readonly property int previewHeight: Math.round(root.previewWidth * 9 / 16)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------------------------------------------------------- state
  readonly property bool streaming: root.opened
  property bool cameraError: false
  property string cameraErrorText: ""
  property string lastSnapshot: ""
  // True once the first preview frame has arrived for the current session.
  property bool hasPreview: false
  // Set briefly when the camera selection changes so the mounted camera
  // stack is torn down and remounted with the new device.
  property bool deviceRestart: false

  readonly property var captureImageCapture: captureLoader.captureImageCapture

  readonly property string statusText: {
    if (!root.hasDevices) return "No camera found"
    if (root.cameraError) return root.cameraErrorText || "Camera error"
    if (root.streaming) {
      var cam = captureLoader.captureCamera
      var r = cam && cam.cameraFormat ? cam.cameraFormat.resolution : null
      var res = r && r.width > 0 ? r.width + "x" + r.height : ""
      var name = root.selectedDevice ? root.selectedDevice.description : ""
      return name + (res !== "" ? " · " + res : "")
    }
    return "Preview off"
  }

  // ------------------------------------------------------------------ util
  function persistSetting(key, value) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.mutateShellConfig !== "function") return
    root.bar.shell.mutateShellConfig(function(config) {
      if (!Util.isPlainObject(config.bar)) config.bar = {}
      if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
      var regions = ["left", "center", "right"]
      for (var r = 0; r < regions.length; r++) {
        var entries = config.bar.layout[regions[r]]
        if (!Array.isArray(entries)) continue
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i]
          if (!entry || String(entry.id) !== root.moduleName) continue
          entry[key] = value
          return
        }
      }
    })
  }

  function notify(title, body) {
    var bin = Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-notification-send"
    Quickshell.execDetached([bin, title, body])
  }

  function takeSnapshot() {
    var ic = root.captureImageCapture
    if (!ic || !ic.readyForCapture) return
    var dir = Quickshell.env("HOME") + "/Pictures"
    var stamp = new Date().toISOString().replace(/[:.]/g, "-")
    root.lastSnapshot = ""
    ic.captureToFile(dir + "/camera-preview-" + stamp + ".jpg")
  }

  // ---------------------------------------------------------------- capture
  // The whole capture stack (CaptureSession + Camera + ImageCapture) is
  // mounted and destroyed together with the popup so the sensor is fully
  // released whenever the panel closes (see the header comment).
  readonly property string previewFile: Quickshell.env("XDG_RUNTIME_DIR") + "/mandavkarpranjal.cam-preview-frame.jpg"

  Loader {
    id: captureLoader
    active: root.opened && root.hasDevices && !root.deviceRestart

    readonly property var captureCamera: item ? item.camera : null
    readonly property var captureImageCapture: item ? item.imageCapture : null

    sourceComponent: Component {
      CaptureSession {
        camera: Camera {
          id: camera
          active: true
          // Passing undefined (not null) keeps the property unset until a
          // device resolves, at which point the binding re-evaluates.
          cameraDevice: root.selectedDevice !== null ? root.selectedDevice : undefined
          onErrorOccurred: function(error, errorString) {
            root.cameraError = error !== Camera.NoError
            root.cameraErrorText = String(errorString || "")
          }
        }
        imageCapture: ImageCapture {
          id: imageCapture
          onImageSaved: function(id, fileName) {
            root.hasPreview = true
            // Cache-busting query so the Image reloads the overwritten file.
            previewImage.source = "file://" + fileName + "?t=" + Date.now()
          }
        }
      }
    }

    onActiveChanged: {
      if (!captureLoader.active) root.hasPreview = false
    }
  }

  onRequestedDeviceIdChanged: {
    root.deviceRestart = true
    Qt.callLater(function() {
      root.deviceRestart = false
    })
  }

  // Poll loop: continuously grab stills for the preview slideshow. The
  // capture backend self-limits to ~15 fps regardless of the interval (the
  // sensor saturates around 65 ms per still capture); a capture already in
  // flight just queues. Note readyForCapture stays false on the FFmpeg
  // backend even while captures succeed, so the call must be unconditional.
  Timer {
    id: previewPoll
    interval: 30
    repeat: true
    running: captureLoader.active && !root.cameraError
    onTriggered: {
      var ic = captureLoader.captureImageCapture
      if (ic) {
        ic.captureToFile(root.previewFile)
      }
    }
  }

  // ------------------------------------------------------------------- bar
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄀"
    active: root.streaming && !root.cameraError
    tooltipText: root.streaming ? "Camera preview (live)" : "Camera preview"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.takeSnapshot()
      else root.toggle()
    }
  }

  // ----------------------------------------------------------------- panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: root.previewWidth + panel.padding * 2
    contentHeight: Math.round(panelColumn.implicitHeight) + panel.padding * 2

    Column {
      id: panelColumn
      anchors.fill: parent
      spacing: Style.space(12)

      // Header: title · camera picker · snapshot
      Item {
        width: parent.width
        height: Math.max(titleLabel.implicitHeight, devicePicker.implicitHeight, snapshotButton.implicitHeight)

        Text {
          id: titleLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Camera"
          color: root.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Dropdown {
          id: devicePicker
          anchors.left: titleLabel.right
          anchors.leftMargin: Style.space(10)
          anchors.right: mirrorButton.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          label: ""
          showLabel: false
          options: root.deviceOptions
          value: root.requestedDeviceId
          foreground: root.barForeground
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          onChanged: function(v) {
            root.persistSetting("device", v)
          }
        }

        Button {
          id: mirrorButton
          anchors.right: snapshotButton.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Mirror"
          iconText: "󰡸"
          selected: root.mirrored
          fontFamily: root.bar.fontFamily
          foreground: root.barForeground
          tooltipText: root.mirrored ? "Preview is mirrored; click to unmirror" : "Preview is not mirrored; click to mirror"
          onClicked: root.persistSetting("mirror", !root.mirrored)
        }

        Button {
          id: snapshotButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "Snapshot"
          iconText: "󰆾"
          fontFamily: root.bar.fontFamily
          foreground: root.barForeground
          onClicked: root.takeSnapshot()
        }
      }

      // Preview: shows the most recent still capture; the capture stack
      // lives in the Loader above.
      Rectangle {
        id: previewFrame
        width: root.previewWidth
        height: root.previewHeight
        radius: Style.cornerRadius
        color: "black"
        clip: true

        Image {
          id: previewImage
          anchors.fill: parent
          fillMode: Image.PreserveAspectFit
          cache: false
          mirror: root.mirrored
          visible: root.hasPreview && !root.cameraError
        }

        // Placeholder states
        Text {
          anchors.centerIn: parent
          visible: !previewImage.visible
          text: !root.hasDevices ? "󰗿  No camera found"
                : root.cameraError ? "󰗿  " + root.statusText
                : root.streaming ? "󰄀  Starting preview…"
                : "󰄀  Preview off"
          color: "#ffffff"
          opacity: 0.75
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      // Status line
      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: statusGlyph
          text: root.streaming && !root.cameraError ? "󰛑" : "󰛒"
          color: root.cameraError ? Color.accent : (root.streaming ? Color.accent : Qt.darker(root.barForeground, 1.3))
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.icon
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          width: parent.width - parent.spacing - statusGlyph.width
          text: root.lastSnapshot !== "" ? "Saved: " + root.lastSnapshot : root.statusText
          color: Qt.darker(root.barForeground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
