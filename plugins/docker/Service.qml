import QtQuick
import Quickshell.Io

Item {
    id: service
    required property var host
    property var rows: []
    property int panels: 0
    property bool online: false
    property string error: ""
    property string message: ""
    readonly property bool busy: scan.running || action.running
    readonly property bool busyAction: action.running
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("manager.py").toString().slice(7))
    readonly property string helper: "/usr/local/lib/orla-docker-manager"
    property bool locked: false
    property bool installed: false
    readonly property bool authorizing: installer.running || (session.running && !online)
    readonly property bool unlocked: session.running && online
    function unlock() {
        if (!panels || !locked || authorizing) return
        message = ""
        if (installed) {
            session.stdinEnabled = true
            session.running = true
        } else installer.running = true
    }
    function refresh() {
        if (session.running) return
        if (scan.running) { pending = true; return }
        scan.command = ["python3", script, panels ? "detail" : "summary"]
        scan.running = true
    }
    property bool pending: false
    onPanelsChanged: {
        if (panels > 0) refresh()
        else if (session.running) {
            session.stdinEnabled = false
            session.running = false
            online = false; rows = []; locked = true
        }
    }
    function run(op, cid) {
        if (action.running) return
        message = ""
        action.command = unlocked ? ["/usr/bin/pkexec", "--disable-internal-agent", helper, op, cid] : ["python3", script, op, cid]
        action.running = true
    }
    Process {
        id: scan
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim() || session.running) return
                const data = JSON.parse(text)
                service.locked = data.locked === true
                service.installed = data.installed === true
                service.online = !data.error
                service.error = service.locked ? "O Docker local exige autenticação." : data.error || data.warning || ""
                service.rows = data.rows || []
            }
        }
        onExited: if (service.pending) { service.pending = false; Qt.callLater(service.refresh) }
    }
    Process {
        id: action
        onExited: code => { if (code !== 0) service.message = "Operação cancelada ou não autorizada." }
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return
                const result = JSON.parse(text)
                service.message = result.error || result.message || ""
                service.refresh()
            }
        }
    }
    Process {
        id: installer
        command: ["/usr/bin/pkexec", "--disable-internal-agent", "/usr/bin/install", "-o", "root", "-g", "root", "-m", "0755", "--", service.script, service.helper]
        onExited: code => {
            service.message = code === 0 ? "Auxiliar instalado. Clique para desbloquear." : "Instalação não concluída."
            service.refresh()
        }
    }
    Process {
        id: session
        command: ["/usr/bin/pkexec", "--disable-internal-agent", service.helper, "watch"]
        stdout: SplitParser {
            onRead: line => {
                if (!service.panels) return
                const data = JSON.parse(line)
                service.rows = data.rows || []
                service.online = !data.error
                service.error = data.error || data.warning || ""
                if (data.error) session.stdinEnabled = false
            }
        }
        onExited: code => {
            service.rows = []; service.online = false; service.locked = true
            if (service.panels) service.message = code === 126 || code === 127 ? "Autenticação cancelada ou negada." : "Sessão de leitura encerrada."
            service.refresh()
        }
    }
    Timer {
        interval: service.panels ? 5000 : 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: service.refresh()
    }
}
