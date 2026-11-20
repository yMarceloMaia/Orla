# Orla

Dock para Omarchy e Hyprland, inspirada na [dock do Grassfield](https://github.com/grassfieldhq/grassfield). A Orla roda em um processo Quickshell separado e exibe os aplicativos do workspace atual em cada monitor. É possível fixar e reordenar ícones, visualizar janelas, minimizá-las e restaurá-las pela dock.

## Instalação

Execute os comandos **como seu usuário, em uma sessão gráfica do Omarchy**. A Orla usa a configuração Lua do Hyprland e o systemd de usuário. A combinação testada foi Omarchy 4.5, Hyprland 0.56.2 e Quickshell 0.3.2 com Qt 6. Outros requisitos são Git, Python 3 com PyGObject (no Arch, `python-gobject`), Zenity e GIO. O instalador verifica os comandos necessários e usa os pacotes já presentes no sistema.

```bash
git clone https://github.com/yMarceloMaia/Orla.git ~/.local/share/orla
cd ~/.local/share/orla
./install.sh
~/.local/bin/orla enable
```

O instalador cria links para o comando em `~/.local/bin`, para o serviço em `~/.config/systemd/user` e para o atalho do launcher em `~/.local/share/applications`. **Mantenha a pasta clonada no lugar** enquanto usar a dock. Os exemplos abaixo pressupõem que `~/.local/bin` esteja no seu `PATH`.

Ao habilitar a Orla, a dock aparece na sessão atual e volta nos próximos logins. Se a dock nativa do Omarchy estiver ativa, a Orla a desativa temporariamente e a reativa ao encerrar. As preferências ficam em `~/.config/orla/settings.json`.

## Usar a dock

| Gesto | Resultado |
|---|---|
| Clique no ícone | Abre o aplicativo, foca sua janela ou minimiza a única janela já focada. |
| Clique com várias janelas | Restaura primeiro uma janela minimizada. Quando todas estão visíveis, alterna entre elas. |
| Passe o ponteiro sobre um app com várias janelas | Mostra miniaturas. Clique em uma para ir diretamente à janela. |
| Botão direito | Mostra as janelas individualmente, ações de minimizar/restaurar e opções de fixação. |
| Arraste arquivos locais sobre um aplicativo | O contorno indica que o aplicativo aceita todos os formatos selecionados. Solte sobre o ícone para abrir os arquivos nele. |
| Botão do meio | Solicita uma nova janela. O toque de três dedos também funciona se o touchpad emitir clique do meio. Aplicativos de instância única podem reutilizar uma janela. |
| Segure e arraste | Os ícones vizinhos abrem espaço. Solte dentro da dock para salvar a ordem ou fora para cancelar. |

Na engrenagem, escolha **Configurar dock…** para ajustar posição, tamanho, ampliação, ocultação automática e pastas de acesso rápido. O menu também dá acesso à lixeira. Em tela cheia, a dock se oculta no monitor correspondente, inclusive quando configurada para ficar sempre visível.

A divisória entre os aplicativos e as pastas também ajusta o tamanho dos ícones. Arraste-a para longe da borda para aumentar ou em direção à borda para diminuir.

Nas configurações, você pode exibir pastas em pilha, até três aplicativos fechados recentemente e uma miniatura separada para cada janela minimizada do workspace. Clique na pasta para explorar os arquivos por data ou nome e na miniatura para restaurar a janela. O menu de aplicativos compatíveis mostra até cinco documentos locais que eles registraram no histórico de recentes do desktop.

## Comandos e recuperação

| Comando | Função |
|---|---|
| `orla settings` | Abre as configurações da dock ativa. |
| `orla enable` / `orla disable` | Ativa ou desativa a dock agora e nos próximos logins. |
| `orla toggle` | Alterna entre os dois estados. Também disponível pelo launcher. |
| `orla recover` | Traz de volta as janelas guardadas pela Orla, mesmo com a dock encerrada. |
| `orla rescue` | Abre ou fecha o workspace especial da dock para acesso manual. |

Janelas minimizadas continuam abertas em um workspace especial separado do scratchpad. No layout *dwindle*, a Orla tenta recompor a divisão original se uma janela vizinha ainda ocupa o espaço liberado. Se o layout mudou, o Hyprland determina a posição. A parada do serviço também tenta recuperar as janelas.

Para ter um atalho de emergência, verifique se a combinação está livre e acrescente esta linha a `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + F12", "Orla: janelas minimizadas", "orla rescue")
```

## Atualizar

Na pasta clonada:

```bash
git pull --ff-only
./install.sh
systemctl --user restart orla.service
```

Reinicie o serviço se a dock estiver em uso. O reinício restaura janelas minimizadas.

## Desinstalar

Na pasta clonada, durante a sessão gráfica, execute `./uninstall.sh`. Para também apagar as preferências, use `./uninstall.sh --purge`. Depois, a pasta clonada pode ser removida. Se tiver personalizado o atalho de emergência, remova também a sua linha de configuração.

## Diagnóstico

```bash
systemctl --user status orla.service
journalctl --user -u orla.service -b -n 50 --no-pager
```

Se uma janela ficar fora de vista, comece por `orla recover`. Se o serviço falhar ao iniciar, confira o log e se a shell do Omarchy está disponível na sessão gráfica.
