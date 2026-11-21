import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C
import Quickshell

FloatingWindow {
    id: page
    required property bool lightMode
    required property bool motion
    required property color systemAccent
    required property var cfg
    signal edited(string key, var value)
    signal requested(string action)
    title: "Orla · Configurações"
    visible: false
    implicitWidth: 580
    implicitHeight: 590
    color: lightMode ? "#eff0f5" : "#202127"
    readonly property color ink: lightMode ? "#24252d" : "#f3f2f6"
    readonly property color muted: lightMode ? "#555965" : "#b9b9c4"
    readonly property color accent: lightMode ? Qt.darker(systemAccent, 1.25) : Qt.lighter(systemAccent, 1.45)

    property int section: 0
    readonly property var sections: ["Aparência", "Janelas", "Widgets", "Pastas"]

    component Caption: Text {
        color: page.muted
        font.pixelSize: 13
        textFormat: Text.PlainText
    }
    component Card: Rectangle {
        Layout.fillWidth: true
        radius: 14
        color: Qt.tint(page.color, Qt.alpha(page.ink, 0.035))
        border.color: Qt.alpha(page.ink, 0.13)
    }
    component Action: C.Button {
        id: button
        implicitHeight: 34
        leftPadding: 12
        rightPadding: 12
        contentItem: Text {
            textFormat: Text.PlainText
            text: button.text
            color: page.ink
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: button.checked ? Qt.alpha(page.accent, 0.20) : Qt.alpha(page.ink, button.hovered ? 0.12 : 0.055)
            border.color: button.visualFocus || button.checked ? page.accent : "transparent"
        }
    }
    component Toggle: C.Switch {
        id: toggle
        Layout.fillWidth: true
        implicitHeight: 36
        padding: 0
        contentItem: Text {
            text: toggle.text
            color: page.ink
            font.pixelSize: 14
            verticalAlignment: Text.AlignVCenter
            rightPadding: 54
        }
        indicator: Rectangle {
            x: toggle.width - width
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 23
            radius: 12
            color: toggle.checked ? page.accent : "#52535e"
            border.color: toggle.activeFocus ? "white" : "transparent"
            Rectangle {
                width: 17
                height: 17
                radius: 9
                y: 3
                x: toggle.checked ? 20 : 3
                color: toggle.checked ? "#35374b" : "#eeeef4"
                Behavior on x {
                    enabled: page.motion
                    NumberAnimation {
                        duration: 110
                    }
                }
            }
        }
    }
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 20
        width: Math.min(parent.width - 40, 760)
        spacing: 12
        Text {
            text: "Configurações da Orla"
            color: page.ink
            font.pixelSize: 24
            font.weight: Font.DemiBold
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: page.sections
                Action {
                    required property int index
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 38
                    leftPadding: 3
                    rightPadding: 3
                    text: modelData
                    checked: page.section === index
                    onClicked: page.section = index
                }
            }
        }
        C.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: scroll.availableWidth
                Card {
                    visible: page.section === 0
                    implicitHeight: group0.implicitHeight + 32
                    ColumnLayout {
                        id: group0
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8
                        Caption {
                            text: "Posição na tela"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Repeater {
                                model: ["Esquerda", "Inferior", "Direita"]
                                Action {
                                    required property int index
                                    required property string modelData
                                    readonly property string edge: ["left", "bottom", "right"][index]
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    id: positionChoice
                                    implicitHeight: 62
                                    contentItem: Column {
                                        spacing: 3
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 32; height: 21; radius: 4
                                            color: "transparent"
                                            border.color: positionChoice.checked ? page.accent : page.muted
                                            Rectangle {
                                                color: positionChoice.checked ? page.accent : page.muted
                                                radius: 1
                                                width: positionChoice.edge === "bottom" ? 16 : 3
                                                height: positionChoice.edge === "bottom" ? 3 : 11
                                                x: positionChoice.edge === "bottom" ? 8 : positionChoice.edge === "left" ? 3 : 26
                                                y: positionChoice.edge === "bottom" ? 15 : 5
                                            }
                                        }
                                        Text {
                                            width: parent.width
                                            text: positionChoice.text
                                            horizontalAlignment: Text.AlignHCenter
                                            color: page.ink
                                            font.pixelSize: 12
                                        }
                                    }
                                    text: modelData
                                    checked: page.cfg.position === edge
                                    onClicked: page.edited("position", edge)
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Caption {
                                text: "Tamanho dos ícones"
                                Layout.fillWidth: true
                            }
                            Caption {
                                text: Math.round(sizeSlider.value) + " px"
                                color: page.ink
                            }
                        }
                        C.Slider {
                            id: sizeSlider
                            Layout.fillWidth: true
                            Accessible.name: "Tamanho dos ícones"
                            from: 30
                            to: 68
                            stepSize: 2
                            value: page.cfg.size
                            palette.highlight: page.accent
                            background: Rectangle {
                                x: sizeSlider.leftPadding
                                y: (sizeSlider.height - height) / 2
                                width: sizeSlider.availableWidth
                                height: 4
                                radius: 2
                                color: Qt.alpha(page.ink, 0.15)
                                Rectangle { width: parent.width * sizeSlider.visualPosition; height: parent.height; radius: 2; color: page.accent }
                            }
                            handle: Rectangle {
                                x: sizeSlider.leftPadding + sizeSlider.visualPosition * (sizeSlider.availableWidth - width)
                                y: (sizeSlider.height - height) / 2
                                width: 16; height: 16; radius: 8
                                color: page.ink
                                border.color: sizeSlider.visualFocus ? page.accent : page.muted
                            }
                            onPressedChanged: if (!pressed && value !== page.cfg.size)
                                page.edited("size", value)
                            onMoved: if (!pressed)
                                page.edited("size", value)
                        }
                        Caption {
                            text: "Tema"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Repeater {
                                model: ["Sistema", "Clara", "Escura"]
                                Action {
                                    required property int index
                                    required property string modelData
                                    property string mode: ["system", "light", "dark"][index]
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    text: modelData
                                    checked: page.cfg.appearance === mode
                                    onClicked: page.edited("appearance", mode)
                                }
                            }
                        }
                        Caption { text: "Estilo da dock" }
                        RowLayout {
                            Layout.fillWidth: true
                            Action {
                                text: "Barra"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                checked: !page.cfg.islands
                                onClicked: page.edited("islands", false)
                            }
                            Action {
                                text: "Ilhas"
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                checked: page.cfg.islands === true
                                onClicked: page.edited("islands", true)
                            }
                        }
                        Toggle {
                            text: "Fundo translúcido"
                            checked: page.cfg.glass
                            onClicked: page.edited("glass", checked)
                        }
                        Toggle {
                            text: "Ampliar ícones sob o ponteiro"
                            checked: page.cfg.zoom
                            onClicked: page.edited("zoom", checked)
                        }
                        Toggle {
                            text: "Animar abertura dos aplicativos"
                            checked: page.cfg.launchAnimation
                            onClicked: page.edited("launchAnimation", checked)
                        }
                        Toggle {
                            text: "Reduzir movimento"
                            checked: page.cfg.reduceMotion
                            onClicked: page.edited("reduceMotion", checked)
                        }
                    }
                }
                Card {
                    visible: page.section === 1
                    implicitHeight: group1.implicitHeight + 32
                    ColumnLayout {
                        id: group1
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8
                        Toggle {
                            text: "Ocultar automaticamente"
                            checked: page.cfg.auto
                            onClicked: page.edited("auto", checked)
                        }
                        Toggle {
                            text: "Indicar aplicativos abertos"
                            checked: page.cfg.indicators
                            onClicked: page.edited("indicators", checked)
                        }
                        Toggle {
                            text: "Mostrar aplicativos recentes"
                            checked: page.cfg.recentApps
                            onClicked: page.edited("recentApps", checked)
                        }
                        Toggle {
                            text: "Mostrar janelas minimizadas na dock"
                            checked: page.cfg.separateMinimized
                            onClicked: page.edited("separateMinimized", checked)
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(page.ink, 0.13) }
                        Action {
                            text: "Restaurar todas as janelas minimizadas"
                            onClicked: page.requested("recover")
                        }
                    }
                }
                Card {
                    visible: page.section === 2
                    implicitHeight: group2.implicitHeight + 32
                    ColumnLayout {
                        id: group2
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8
                        Toggle {
                            text: "Mostrar bandeja de arquivos"
                            checked: page.cfg.fileTray !== false
                            onClicked: page.edited("fileTray", checked)
                        }
                        Toggle {
                            text: "Mostrar player de mídia"
                            checked: page.cfg.mediaPlayer !== false
                            onClicked: page.edited("mediaPlayer", checked)
                        }
                        Toggle {
                            text: "Mostrar atividade do GitHub"
                            checked: page.cfg.githubWidget === true
                            onClicked: page.edited("githubWidget", checked)
                        }
                        Toggle {
                            visible: page.cfg.githubWidget === true
                            text: "Alertar sobre comentários e conflitos nos meus PRs"
                            checked: page.cfg.githubAlerts !== false
                            onClicked: page.edited("githubAlerts", checked)
                        }
                        Toggle {
                            text: "Mostrar uso do Claude e Codex"
                            checked: page.cfg.usageWidget === true
                            onClicked: page.edited("usageWidget", checked)
                        }
                    }
                }
                Card {
                    visible: page.section === 3
                    implicitHeight: group3.implicitHeight + 32
                    ColumnLayout {
                        id: group3
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8
                        Toggle {
                            text: "Mostrar pastas como pilhas"
                            checked: page.cfg.stacks
                            onClicked: page.edited("stacks", checked)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Caption {
                                text: "Pastas de acesso rápido"
                                Layout.fillWidth: true
                            }
                            Action {
                                text: "Adicionar…"
                                onClicked: page.requested("folder")
                            }
                        }
                        Repeater {
                            model: page.cfg.folders
                            RowLayout {
                                required property string modelData
                                Layout.fillWidth: true
                                Text {
                                    text: parent.modelData
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    elide: Text.ElideMiddle
                                    color: page.ink
                                    font.pixelSize: 14
                                }
                                Action {
                                    text: "Remover"
                                    Accessible.name: "Remover " + parent.modelData
                                    onClicked: page.edited("folders", page.cfg.folders.filter(f => f !== parent.modelData))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
