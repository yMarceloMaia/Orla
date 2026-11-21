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
    implicitWidth: 510
    implicitHeight: 600
    color: lightMode ? "#eff0f5" : "#202127"
    readonly property color ink: lightMode ? "#24252d" : "#f3f2f6"
    readonly property color muted: lightMode ? "#555965" : "#b9b9c4"
    readonly property color accent: lightMode ? Qt.darker(systemAccent, 1.25) : Qt.lighter(systemAccent, 1.45)

    component Caption: Text {
        color: page.muted
        font.pixelSize: 13
        textFormat: Text.PlainText
    }
    component Card: Rectangle {
        Layout.fillWidth: true
        radius: 14
        color: page.lightMode ? "#fcfcff" : "#2b2c33"
        border.color: page.lightMode ? "#cdd0db" : "#414249"
    }
    component Action: C.Button {
        id: button
        implicitHeight: 34
        leftPadding: 12
        rightPadding: 12
        contentItem: Text {
            text: button.text
            color: button.checked ? (page.lightMode ? "white" : "#171821") : page.ink
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: button.checked ? page.accent : button.hovered ? (page.lightMode ? "#d4d9e5" : "#50515f") : (page.lightMode ? "#e4e7ee" : "#393a44")
            border.color: button.activeFocus ? page.accent : "transparent"
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
    C.ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: scroll.availableWidth
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 22
                Layout.bottomMargin: 4
                spacing: 4
                Text {
                    text: "Orla"
                    color: page.accent
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Configurações da dock"
                    color: page.ink
                    font.pixelSize: 26
                    font.weight: Font.DemiBold
                }
            }
            Card {
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                implicitHeight: appearance.implicitHeight + 28
                ColumnLayout {
                    id: appearance
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
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
                        onPressedChanged: if (!pressed && value !== page.cfg.size)
                            page.edited("size", value)
                        onMoved: if (!pressed)
                            page.edited("size", value)
                    }
                    Caption {
                        text: "Aparência"
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
                                text: modelData
                                checked: page.cfg.appearance === mode
                                onClicked: page.edited("appearance", mode)
                            }
                        }
                    }
                    Toggle {
                        text: "Fundo translúcido"
                        checked: page.cfg.glass
                        onClicked: page.edited("glass", checked)
                    }
                    Toggle {
                        text: "Reduzir movimento"
                        checked: page.cfg.reduceMotion
                        onClicked: page.edited("reduceMotion", checked)
                    }
                    Toggle {
                        text: "Animar abertura dos aplicativos"
                        checked: page.cfg.launchAnimation
                        onClicked: page.edited("launchAnimation", checked)
                    }
                    Toggle {
                        text: "Indicar aplicativos abertos"
                        checked: page.cfg.indicators
                        onClicked: page.edited("indicators", checked)
                    }
                    Toggle {
                        text: "Mostrar janelas minimizadas na dock"
                        checked: page.cfg.separateMinimized
                        onClicked: page.edited("separateMinimized", checked)
                    }
                    Toggle {
                        text: "Mostrar aplicativos recentes"
                        checked: page.cfg.recentApps
                        onClicked: page.edited("recentApps", checked)
                    }
                    Toggle {
                        text: "Mostrar player durante a reprodução"
                        checked: page.cfg.mediaPlayer !== false
                        onClicked: page.edited("mediaPlayer", checked)
                    }
                    Toggle {
                        text: "Mostrar pastas como pilhas"
                        checked: page.cfg.stacks
                        onClicked: page.edited("stacks", checked)
                    }
                    Toggle {
                        text: "Ocultar automaticamente"
                        checked: page.cfg.auto
                        onClicked: page.edited("auto", checked)
                    }
                    Toggle {
                        text: "Ampliar ícones sob o ponteiro"
                        checked: page.cfg.zoom
                        onClicked: page.edited("zoom", checked)
                    }
                }
            }
            Card {
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                implicitHeight: paths.implicitHeight + 28
                ColumnLayout {
                    id: paths
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8
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
            Action {
                Layout.leftMargin: 20
                Layout.bottomMargin: 18
                text: "Restaurar todas as janelas minimizadas"
                onClicked: page.requested("recover")
            }
        }
    }
}
