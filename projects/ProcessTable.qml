import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: table
    required property var processes
    required property color ink
    required property color tone
    required property string projectId
    property int expanded: -1
    property string sortBy: "cpu"
    readonly property color muted: Qt.alpha(ink, 0.68)
    readonly property bool wide: width >= 490
    readonly property int pidWidth: wide ? 76 : 52
    readonly property int cpuWidth: wide ? 80 : 52
    readonly property int ramWidth: wide ? 100 : 70
    spacing: 0
    onProjectIdChanged: expanded = -1
    function sizeText(n) {
        if (n == null)
            return "—";
        for (const [factor, unit] of [[1073741824, "GiB"], [1048576, "MiB"], [1024, "KiB"]])
            if (n >= factor)
                return Number((n / factor).toFixed(1)) + " " + unit;
        return n + " B";
    }
    function duration(s) {
        if (s >= 3600)
            return Math.floor(s / 3600) + " h " + Math.floor((s % 3600) / 60) + " min";
        if (s >= 60)
            return Math.floor(s / 60) + " min " + (s % 60) + " s";
        return s + " s";
    }
    function stateName(s) {
        return ({
                R: "Em execução",
                S: "Em espera",
                D: "Aguardando E/S",
                T: "Suspenso",
                t: "Em depuração",
                Z: "Zumbi",
                I: "Ocioso",
                X: "Encerrado"
            })[s] || s;
    }
    component Cell: Text {
        color: table.ink
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.pixelSize: 13
    }
    component SortButton: ToolButton {
        id: sort
        required property string field
        padding: 0
        implicitHeight: 28
        Accessible.name: "Ordenar por " + text
        onClicked: table.sortBy = field
        contentItem: Cell {
            text: sort.text + (table.sortBy === sort.field ? " ↓" : "")
            color: table.sortBy === sort.field ? table.tone : table.muted
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: "transparent"
            border.color: sort.visualFocus ? table.tone : "transparent"
        }
    }
    Cell {
        Layout.topMargin: 6
        Layout.bottomMargin: 5
        text: "Processos locais (" + table.processes.length + ")"
        font.weight: Font.DemiBold
        font.pixelSize: 15
    }
    Cell {
        visible: !table.processes.length
        text: "Nenhum processo local identificado."
        color: table.muted
    }
    RowLayout {
        visible: table.processes.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        spacing: 8
        Cell {
            Layout.fillWidth: true
            text: "Processo"
            color: table.muted
        }
        Cell {
            Layout.preferredWidth: table.pidWidth
            horizontalAlignment: Text.AlignRight
            text: "PID"
            color: table.muted
        }
        SortButton {
            Layout.preferredWidth: table.cpuWidth
            text: "CPU"
            field: "cpu"
        }
        SortButton {
            Layout.preferredWidth: table.ramWidth
            text: "RAM"
            field: "ram"
        }
        Item {
            Layout.preferredWidth: 14
        }
    }
    Repeater {
        model: table.processes.slice().sort((a, b) => (b[table.sortBy] ?? -1) - (a[table.sortBy] ?? -1) || a.pid - b.pid)
        delegate: ColumnLayout {
            id: row
            required property var modelData
            readonly property bool open: table.expanded === modelData.pid
            Layout.fillWidth: true
            spacing: 0
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Qt.alpha(table.ink, 0.10)
            }
            ToolButton {
                id: toggle
                Layout.fillWidth: true
                implicitHeight: 36
                horizontalPadding: 10
                verticalPadding: 0
                Accessible.name: row.modelData.name + ", PID " + row.modelData.pid
                Accessible.description: row.open ? "Recolher detalhes" : "Mostrar detalhes"
                onClicked: table.expanded = row.open ? -1 : row.modelData.pid
                background: Rectangle {
                    radius: 5
                    color: Qt.alpha(table.tone, row.open ? 0.08 : toggle.hovered ? 0.05 : 0)
                    border.color: toggle.visualFocus ? table.tone : "transparent"
                }
                contentItem: RowLayout {
                    spacing: 8
                    Cell {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        font.weight: Font.DemiBold
                    }
                    Cell {
                        Layout.preferredWidth: table.pidWidth
                        horizontalAlignment: Text.AlignRight
                        text: row.modelData.pid
                        color: table.muted
                    }
                    Cell {
                        Layout.preferredWidth: table.cpuWidth
                        horizontalAlignment: Text.AlignRight
                        text: row.modelData.cpu == null ? "—" : (row.modelData.cpu >= 90 ? "▲ " : "") + row.modelData.cpu.toFixed(1) + "%"
                    }
                    Cell {
                        Layout.preferredWidth: table.ramWidth
                        horizontalAlignment: Text.AlignRight
                        text: (row.modelData.memory === "PSS" ? "" : "≈ ") + table.sizeText(row.modelData.ram)
                    }
                    Cell {
                        Layout.preferredWidth: 14
                        text: row.open ? "⌄" : "›"
                        horizontalAlignment: Text.AlignRight
                        color: table.tone
                    }
                }
            }
            GridLayout {
                visible: row.open
                columns: table.wide ? 2 : 1
                Layout.fillWidth: true
                Layout.margins: 10
                columnSpacing: 16
                rowSpacing: 5
                Repeater {
                    model: row.open ? [["Comando", row.modelData.command], ["Estado", table.stateName(row.modelData.state)], ["Tempo ativo", table.duration(row.modelData.seconds)], ["Associação", row.modelData.association], ["Leitura", table.sizeText(row.modelData.read)], ["Escrita", table.sizeText(row.modelData.write)], ["Memória", row.modelData.memory]] : []
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6
                        Cell {
                            text: modelData[0]
                            color: table.muted
                        }
                        Cell {
                            Layout.fillWidth: true
                            text: modelData[1] ?? "—"
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }
        }
    }
}
