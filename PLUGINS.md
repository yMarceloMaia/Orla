# Orla plugins · API v1

Official widgets live under `plugins/<name>/` in this repository. Personal and third-party plugins can live in separate repositories. Install a third-party plugin by placing its directory under `~/.config/orla/plugins/` with the manifest at the top of that directory. Enable it in **Settings → Widgets**. To remove it, disable it and delete its directory. Preferences live in `~/.config/orla/settings.json`.

## Minimal example

Create a folder called `clock` with these two files.

**manifest.json**

```json
{
  "apiVersion": 1,
  "id": "example.clock",
  "name": "Clock",
  "widget": "Widget.qml"
}
```

**Widget.qml**

```qml
import QtQuick

Rectangle {
    id: tile
    required property var host
    implicitWidth: label.implicitWidth + 16
    implicitHeight: host.edge
    radius: 8
    color: host.surface

    Text {
        id: label
        anchors.centerIn: parent
        color: tile.host.ink
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: label.text = Qt.formatTime(new Date(), "HH:mm")
    }
}
```

## Plugin contract

- Choose a stable ID made of lowercase letters and digits, with dots or hyphens between segments. Official IDs take precedence. Third-party plugins start disabled.
- Orla creates one widget per monitor and supplies the required `host` property. Use `implicitWidth` and `implicitHeight` to size the item. Set a `keepOpen` boolean while an interactive popup needs the dock to stay visible.
- The widget receives `host.background`, `host.surface`, `host.accent`, and `host.ink`. Use `host.edge` for the icon size. The host also exposes `extent`, `vertical`, `leftEdge`, `screenWidth`, `screenHeight`, and `shown`.
- Widgets with wider summaries can expose `dockExtraWidth` for the space they need beyond `host.preferredEdge`. Use only `host.edge` in width when `host.compact` is true. Calculate `dockExtraWidth` from the preferred layout independently of responsive compaction.
- Use `host.preference("key", defaultValue)` and `host.savePreference("key", value)`. Preference keys accept letters, digits, hyphens, and underscores. Preferences are scoped to the plugin ID.
- Set `"service": "Service.qml"` in the manifest to share data or polling across monitors. The service declares `required property var host` and runs once per enabled dock session. Widgets access it through `host.service`. Disabling the plugin unloads the service and widget instances.
- Entry paths are relative to the manifest. Plugin QML runs with the permissions of the desktop user. Review third-party plugins before enabling them.

For complete examples, see [File Tray](plugins/tray/) and [GitHub Activity](plugins/github/).
