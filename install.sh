#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")" && pwd -P)
for tool in python3 quickshell qs hyprctl omarchy systemctl zenity gio; do
  command -v "$tool" >/dev/null || { echo "Comando necessário: $tool" >&2; exit 1; }
done
sources=(orla orla.service orla-toggle.desktop)
targets=("$HOME/.local/bin/orla" "$HOME/.config/systemd/user/orla.service" "$HOME/.local/share/applications/orla-toggle.desktop")
for i in "${!targets[@]}"; do
  path=${targets[i]}
  if [[ -e $path || -L $path ]]; then
    [[ $path -ef "$root/${sources[i]}" ]] && continue
    # Launcher gerado pelas primeiras instalações locais da Orla.
    if [[ $i == 2 && ! -L $path ]] && cmp -s "$path" <(sed "s|^Exec=.*|Exec=$HOME/.local/bin/orla toggle|" "$root/orla-toggle.desktop"); then continue; fi
    echo "Já existe outro arquivo em $path. Instalação interrompida." >&2
    exit 1
  fi
done
for i in "${!targets[@]}"; do
  path=${targets[i]}
  mkdir -p -- "$(dirname -- "$path")"
  [[ -e $path ]] || ln -s -- "$root/${sources[i]}" "$path"
done
systemctl --user daemon-reload
echo 'Instalado. Para iniciar e habilitar nos próximos logins, execute ~/.local/bin/orla enable'
