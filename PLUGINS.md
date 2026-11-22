# Plugins da Orla · API v1

Os widgets oficiais vivem em `plugins/<nome>/` neste repositório e acompanham a versão da dock. Um plugin pessoal ou publicado por terceiros pode ter seu próprio repositório. Para instalá-lo, coloque sua pasta em `~/.config/orla/plugins/`, com o manifesto diretamente dentro dela. Habilite-o na seção de widgets das configurações da Orla. Para remover, desative-o e apague a pasta. Preferências salvas ficam em `~/.config/orla/settings.json`.

## Exemplo mínimo

Crie uma pasta chamada `relogio` com estes dois arquivos.

**manifest.json**

```json
{
  "apiVersion": 1,
  "id": "exemplo.relogio",
  "name": "Relógio",
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

## Contrato

- Cada plugin tem um ID estável composto de letras minúsculas e números, com ponto ou hífen entre segmentos. A Orla prioriza IDs oficiais e inicia novos plugins externos desativados.
- A Orla cria um widget por monitor e fornece a propriedade obrigatória `host`. Defina o tamanho do item usando `implicitWidth` e `implicitHeight`. Um widget com painel aberto pode expor `property bool keepOpen` para manter a dock visível durante a interação.
- O widget recebe as cores `host.background`, `surface`, `accent` e `ink`. Para dimensionamento, use `host.edge` (tamanho do ícone), `extent`, `vertical`, `leftEdge`, `screenWidth` e `screenHeight`. `host.shown` acompanha a visibilidade da dock.
- Um widget que oferece um resumo largo pode expor `dockExtraWidth` com o espaço adicional além de `host.preferredEdge`. Quando `host.compact` estiver ativo, use somente `host.edge` de largura. Calcule `dockExtraWidth` a partir do formato preferido, independentemente do modo compacto aplicado pelo encaixe.
- Use `host.preference("chave", valorPadrao)` e `host.savePreference("chave", valor)` para configurações próprias. Use letras, números, hífen ou sublinhado na chave. O ID do plugin separa as preferências.
- Para compartilhar dados ou consultas entre monitores, acrescente `"service": "Service.qml"` ao manifesto. O serviço também declara `required property var host`. Ele existe uma vez por sessão da dock enquanto habilitado. Cada widget acessa a mesma instância em `host.service`. Desativar o plugin descarrega seus widgets e seu serviço.
- Os caminhos de entrada são relativos à pasta do manifesto. Plugins executam código QML com as permissões do usuário da sessão. Revise a origem antes de habilitar um plugin externo.

Para exemplos com dados reais, consulte a [bandeja](plugins/tray/) e o [GitHub](plugins/github/).
