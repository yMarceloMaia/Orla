import QtQuick
import Quickshell.Io

DropArea {
    id: area
    required property string helper
    required property string appId
    required property bool light
    signal launchRequested
    keys: ["text/uri-list"]
    property var paths: []
    property bool compatible: false
    function urlsOf(event) {
        return Array.from(event.urls || [], u => u.toString());
    }
    function reset() {
        paths = [];
        compatible = false;
    }
    onEntered: event => {
        reset();
        const urls = urlsOf(event);
        if (!appId || !urls.length || urls.length > 128 || !(event.supportedActions & Qt.CopyAction)) {
            event.accepted = false;
            return;
        }
        paths = urls;
        event.accept(Qt.CopyAction);
    }
    onPositionChanged: event => {
        if (paths.length && (event.supportedActions & Qt.CopyAction))
            event.accept(Qt.CopyAction);
        else
            event.accepted = false;
    }
    onExited: reset()
    onDropped: event => {
        const urls = urlsOf(event);
        if (compatible && (event.supportedActions & Qt.CopyAction) && JSON.stringify(urls) === JSON.stringify(paths)) {
            event.accept(Qt.CopyAction);
            launchRequested();
            launcher.exec([helper, "drop-open", appId, ...urls]);
        } else
            event.accepted = false;
        reset();
    }
    Process {
        id: checker
        command: [area.helper, "drop-check", area.appId, ...area.paths]
        onExited: (code, status) => {
            if (area.paths.length && !delay.running)
                area.compatible = code === 0 && JSON.stringify(startedPaths) === JSON.stringify(area.paths);
            if (area.paths.length && JSON.stringify(startedPaths) !== JSON.stringify(area.paths))
                delay.restart();
        }
        property var startedPaths: []
    }
    onPathsChanged: if (paths.length)
        delay.restart()
    Timer {
        id: delay
        interval: 1
        onTriggered: if (area.paths.length && !checker.running) {
            checker.startedPaths = area.paths.slice();
            checker.running = true;
        }
    }
    Process {
        id: launcher
    }
    Rectangle {
        anchors.fill: parent
        radius: 12
        visible: area.compatible
        color: area.light ? "#303253a9" : "#365c91d6"
        border.width: 2
        border.color: area.light ? "#344da0" : "#bdd7ff"
    }
}
