# Orla

Orla is a per-workspace dock for Omarchy and Hyprland, inspired by the [Grassfield dock](https://github.com/grassfieldhq/grassfield). It runs in a separate Quickshell process and shows the apps on each monitor's current workspace. Pin and reorder apps, preview their windows, and minimize or restore them from the dock.

## Installation

Run these commands **as your regular user in an Omarchy graphical session**. Orla uses Hyprland's Lua configuration and a systemd user service. The tested setup is Omarchy 4.5, Hyprland 0.56.2, and Quickshell 0.3.2 with Qt 6. It also requires Git, Python 3 with PyGObject (`python-gobject` on Arch), Zenity, and GIO. The installer checks for the commands it needs.

```bash
git clone https://github.com/yMarceloMaia/Orla.git ~/.local/share/orla
cd ~/.local/share/orla
./install.sh
~/.local/bin/orla enable
```

The installer links the command into `~/.local/bin`, the service into `~/.config/systemd/user`, and the launcher entry into `~/.local/share/applications`. Keep the checkout in place. The examples below assume `~/.local/bin` is on your PATH.

Enabling Orla starts it for the current session and future logins. If the native Omarchy dock is active, Orla temporarily disables it and re-enables it on exit. Orla stores preferences in `~/.config/orla/settings.json`.

## Using the dock

| Gesture | Result |
|---|---|
| Click an app icon | Launches the app, focuses its window, or minimizes its only window if already focused. |
| Click an app with several windows | Restores a minimized window first. When all are visible, cycles through them. |
| Hover over an app with several windows | Shows previews. Click a preview to focus or restore its window. |
| Right-click an app | Shows individual windows, minimize and restore actions, and pinning options. |
| Drag files onto an app | An outline indicates that the app accepts the selected files. Drop them to open them in the app. |
| Middle-click an app | Requests a new window. A three-finger tap also works when configured as a middle-click. Single-instance apps may reuse a window. |
| Drag an app icon | Reorders it. Drop inside the dock to save or outside to cancel. |

The gear menu opens **Dock settings**, where you can change the position, icon size, hover magnification, auto-hide behavior, and quick-access folders. The menu also provides access to the trash. A fullscreen window hides Orla on its monitor.

Open **Appearance** to choose **Bar**, **Islands**, or **3D Shelf**. Bar and 3D Shelf support Classic, Paper, and Neon finishes. On smaller displays, Orla compacts widgets and reduces icon size. The **+N** button gives you access to items that do not fit. Drag the divider between apps and folders away from the screen edge to increase the icon size, or towards the edge to decrease it.

Orla can show folders as stacks, up to three recently closed apps, and separate previews for minimized windows. Click a stack to sort and browse files, or click a minimized preview to restore the window. Compatible apps can show up to five documents from the desktop's recent-files history.

### Window overview

Run `orla overview` to toggle the overview for the active workspace on the focused monitor. It includes windows minimized from that workspace. Click a thumbnail or use the arrow keys and **Enter** to focus or restore a window. **Esc** closes the overview.

To bind it to **Super + Alt + D**, add this line to `~/.config/hypr/bindings.lua`.

```lua
o.rebind("SUPER + ALT + D", "Orla window overview", "~/.local/bin/orla overview")
```

## Plugins and widgets

Orla ships with Docker Manager, Media Player, GitHub Activity, Claude and Codex Usage, File Tray, and the project widgets. See the [plugin API](PLUGINS.md) to install or build a plugin. See the [project widget guide](projects/README.md) for resource monitoring and project commands.

### File Tray

Drop local files on the tray icon or in its open panel. The count is shared across monitors and workspaces. Drag the tray icon to pass the last item to another app, or open the tray and drag a specific item. **×** removes the reference from the tray. The tray clears when Orla restarts.

### Media Player

The player shows the current track and playback controls from an MPRIS-compatible app. Right-click the widget to switch between the full player and the icon. In icon mode, hover to show the controls.

### Docker Manager

Enable **Docker Manager** in **Settings → Widgets**. It uses the `docker` CLI and the context available to the Orla user service. If the local engine requires authentication, click **Install authentication helper** once, then **Unlock Docker**. The system's Polkit dialog handles authentication. The installer copies `plugins/docker/manager.py` from your checkout into `/usr/local/lib/orla-docker-manager` as a root-owned executable. Use a trusted checkout when installing it.

The unlocked session reads data from the local Docker engine for up to ten minutes and ends when the last panel closes. Control actions, health checks, shell access, and logs require separate authorization. Terminals opened for a shell or live logs have their own lifetime. To update the helper, run `sudo install -o root -g root -m 0755 -- plugins/docker/manager.py /usr/local/lib/orla-docker-manager` from the updated checkout. To remove it, run `sudo rm -- /usr/local/lib/orla-docker-manager`.

Click the widget to browse containers grouped by Compose project and see CPU and memory metrics. Containers without the `com.docker.compose.project` label appear under **No Compose project**. Click or right-click a container for its controls, recent health checks, and published TCP ports. Published-port links use HTTPS for container port 443 and HTTP for other ports. Shell and live logs open in the default terminal via `xdg-terminal-exec`. Shell access requires `sh` in the container.

### Optional integrations

Enable the corresponding widget in **Settings → Widgets** after signing in to the required CLI. Executables need to be on the systemd user service's PATH.

| Integration | Setup |
|---|---|
| GitHub | Install the GitHub CLI and run `gh auth login --hostname github.com`. Orla reads contributions, pull requests, and checks using the active account. Comment and merge conflict notifications display the repository and PR number. |
| Claude | Run `claude auth login`. Orla reads the local OAuth credential from `~/.claude/.credentials.json` to query plan limits from Anthropic's API. |
| Codex | Run `codex login` with the account you want to monitor. Orla queries the local CLI through `codex app-server` and `account/rateLimits/read`. |

On another computer, sign in with the accounts you want to use there.

#### Second Claude profile

The widget displays **Claude** and **Codex** by default. To add another Claude account, choose a separate profile directory and a display name.

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude auth login
orla set extraClaudeProfile '{"name":"Work","directory":"~/.claude-work"}'
```

Click **Refresh** in the usage panel. To remove the profile from Orla, run `orla set extraClaudeProfile null`. The CLI remains signed in.

#### GitHub organization filter

By default, the widget includes organizations accessible to the account. To exclude one from pull requests, notifications, and the contribution calendar, pass its GitHub login.

```bash
orla set githubExcludedOrg '"example-org"'
```

Click **Refresh** in the GitHub widget. Clear the filter with `orla set githubExcludedOrg '""'`.

## Commands and window recovery

| Command | Result |
|---|---|
| `orla settings` | Opens the dock settings. |
| `orla overview` | Toggles the window overview. |
| `orla enable` / `orla disable` | Enables or disables the dock now and at future logins. |
| `orla toggle` | Toggles the dock. Also available in the app launcher. |
| `orla recover` | Restores windows minimized by Orla, even if the dock is closed. |
| `orla rescue` | Opens or closes Orla's special workspace for manual access. |

Minimized windows stay open in a special workspace separate from the scratchpad. With *dwindle*, Orla attempts to recreate the original split if a neighboring window still occupies the space. If the layout has changed, Hyprland places the restored window. Stopping the service also attempts to recover minimized windows.

To add an emergency shortcut, check that the key combination is free and add this line to `~/.config/hypr/bindings.lua`.

```lua
o.bind("SUPER + CTRL + F12", "Orla minimized windows", "orla rescue")
```

## Updating

Run these commands from the existing checkout.

```bash
git pull --ff-only
./install.sh
systemctl --user restart orla.service
```

Restart the service if the dock is running. A restart restores minimized windows.

## Uninstalling

Run `./uninstall.sh` from the checkout in a graphical session. Use `./uninstall.sh --purge` to remove the dock preferences as well. After uninstalling, you can remove the checkout and any shortcuts you added for Orla.

## Troubleshooting

```bash
systemctl --user status orla.service
journalctl --user -u orla.service -b -n 50 --no-pager
```

If a window is out of sight, start with `orla recover`. If the service fails to start, check its logs and confirm the Omarchy shell is available in the graphical session.

## License

Orla is released under the [MIT License](LICENSE).
