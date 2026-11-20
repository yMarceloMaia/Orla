#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")" && pwd -P)
cmd="$HOME/.local/bin/orla"
unit="$HOME/.config/systemd/user/orla.service"
launcher="$HOME/.local/share/applications/orla-toggle.desktop"
[[ $cmd -ef "$root/orla" && $unit -ef "$root/orla.service" ]] || { echo 'Execute a partir da cópia instalada da Orla.' >&2; exit 1; }
"$cmd" disable
"$cmd" recover
"$cmd" native-back
bindings="$HOME/.config/hypr/bindings.lua"
if [[ -f $bindings ]] && grep -Fxq 'o.bind("SUPER + CTRL + F12", "Orla: janelas minimizadas", "orla rescue")' "$bindings"; then
  sed -i '/^-- Orla: acesso independente às janelas guardadas$/d; /^o.bind("SUPER + CTRL + F12", "Orla: janelas minimizadas", "orla rescue")$/d' "$bindings"
  hyprctl reload
  hyprctl configerrors
fi
if [[ $launcher -ef "$root/orla-toggle.desktop" ]] || cmp -s "$launcher" <(sed "s|^Exec=.*|Exec=$HOME/.local/bin/orla toggle|" "$root/orla-toggle.desktop"); then
  unlink "$launcher"
fi
unlink "$unit"
unlink "$cmd"
systemctl --user daemon-reload
if [[ ${1:-} == --purge && -d $HOME/.config/orla ]]; then
  rm -f -- "$HOME/.config/orla/settings.json"
  rmdir --ignore-fail-on-non-empty "$HOME/.config/orla"
fi
