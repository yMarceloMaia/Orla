pragma Singleton
import QtQuick
import Quickshell.Io

Item {
    id: hub
    property int clients: 0
    property int monitors: 0
    property int panels: 0
    property int intervalSeconds: 4
    property int idleSeconds: 30
    property var docker: null
    property var projects: []
    property var runs: []
    property string error: ""
    property bool ticking: false
    signal panelOpened(var window)
    signal logResult(string run, var lines)
    function send(message) {
        if (!worker.running)
            return;
        worker.write(JSON.stringify(message) + "\n");
    }
    function tick() {
        if (ticking || !worker.running)
            return;
        ticking = true;
        send({
            op: "tick",
            monitor: monitors > 0 || panels > 0,
            detail: panels > 0
        });
    }
    function syncDocker() {
        send({
            op: "docker",
            rows: docker?.online ? docker.rows : []
        });
    }
    onDockerChanged: syncDocker()
    Connections {
        target: hub.docker
        function onRowsChanged() {
            hub.syncDocker();
        }
    }
    Binding {
        target: hub.docker
        property: "projectMetrics"
        value: hub.monitors > 0 && hub.panels > 0
        when: !!hub.docker
    }
    Process {
        id: worker
        command: ["python3", "-u", decodeURIComponent(Qt.resolvedUrl("backend.py").toString().slice(7))]
        stdinEnabled: true
        onExited: if (hub.clients > 0) {
            hub.ticking = false;
            hub.error = "O serviço de projetos foi interrompido. Reconectando…";
            retry.restart();
        }
        onStarted: {
            hub.ticking = false;
            hub.syncDocker();
            hub.tick();
        }
        stdout: SplitParser {
            onRead: line => {
                const result = JSON.parse(line);
                if (result.tick || result.error)
                    hub.ticking = false;
                if (result.error)
                    hub.error = result.error;
                if (result.projects) {
                    hub.projects = result.projects;
                    hub.runs = result.runs;
                }
                if (result.logs)
                    hub.logResult(result.run, result.logs);
            }
        }
    }
    Timer {
        running: hub.clients > 0
        repeat: true
        interval: (hub.panels ? hub.intervalSeconds : hub.idleSeconds) * 1000
        onTriggered: hub.tick()
    }
    Timer {
        id: retry
        interval: 2000
        onTriggered: if (hub.clients > 0)
            worker.running = true
    }
    onClientsChanged: {
        if (clients > 0 && !worker.running)
            worker.running = true;
        else if (!clients) {
            retry.stop();
            worker.running = false;
            projects = [];
            runs = [];
        }
    }
    onPanelsChanged: tick()
}
