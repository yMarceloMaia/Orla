import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: service
    required property var host
    readonly property bool busy: usageFetch.running
    function refresh() { usageFetch.running = true; }
    property var planUsage: []
    Process {
        id: usageFetch
        command: [host.helper, "usage"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim()) service.planUsage = JSON.parse(text)
        }
    }
    Timer {
        interval: 600000
        running: true
        triggeredOnStart: true
        repeat: true
        onTriggered: usageFetch.running = true
    }
}
