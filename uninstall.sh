#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")" && pwd -P)
cmd="$HOME/.local/bin/orla"
unit="$HOME/.config/systemd/user/orla.service"
launcher="$HOME/.local/share/applications/orla-toggle.desktop"
[[ $cmd -ef "$root/orla" && $unit -ef "$root/orla.service" ]] || { echo 'Run this from the installed Orla checkout.' >&2; exit 1; }
"$cmd" disable
"$cmd" recover
"$cmd" native-back
bindings="$HOME/.config/hypr/bindings.lua"
if [[ -f $bindings ]] && grep -Eq '^o\.bind\("SUPER \+ CTRL \+ F12", "(Orla: janelas minimizadas|Orla minimized windows)", "orla rescue"\)$' "$bindings"; then
  sed -Ei '/^-- Orla: acesso independente às janelas guardadas$/d; /^o\.bind\("SUPER \+ CTRL \+ F12", "(Orla: janelas minimizadas|Orla minimized windows)", "orla rescue"\)$/d' "$bindings"
  hyprctl reload
  hyprctl configerrors
fi
generated=$(sed "s|^Exec=.*|Exec=$HOME/.local/bin/orla toggle|" "$root/orla-toggle.desktop")
if [[ $launcher -ef "$root/orla-toggle.desktop" ]] ||
   cmp -s "$launcher" <(printf '%s\n' "$generated") ||
   cmp -s "$launcher" <(printf '%s\n' "${generated/Toggle dock/Ativar ou desativar dock}"); then
  unlink "$launcher"
fi
unlink "$unit"
unlink "$cmd"
systemctl --user daemon-reload
if [[ ${1:-} == --purge && -d $HOME/.config/orla ]]; then
  rm -f -- "$HOME/.config/orla/settings.json" "$HOME/.config/orla/recent-apps.json"
  rmdir --ignore-fail-on-non-empty "$HOME/.config/orla"
fi
