# Project widgets

Enable **Project Resources**, **Project Commands**, or both under **Settings → Widgets**. They share one project registry and one Python helper per session. Commands run as the current user in transient systemd units.

## Adding and monitoring projects

**Add folder** registers a directory. **Discover projects** accepts a folder with project markers or scans its direct children. Orla revisits discovery folders and remembers manually removed projects. Rename a project with **Configure**. Its internal ID stays stable.

The monitor uses each managed run's cgroup to attribute processes. For other processes, it estimates project ownership from the working directory, absolute paths in arguments, and ancestry. CPU usage of 100% represents one core. A triangle marks processes using at least 90% of a core in the current sample. Orla uses PSS for local memory when available and labels RSS estimates. Disk counters accumulate from the start of each process.

**Project Commands → System ports** lists visible TCP listeners and bound UDP sockets in the host network namespace. It shows the address and any process name and PID Orla can read. The **Ports** tab inside a project lists sockets associated with that project and links for its published Docker ports. The filter matches the fields available in each view.

Use **Intervals** to adjust sampling with the panel open or closed. The defaults are 4 and 30 seconds. CPU and RAM charts retain 60 samples and reset when the helper restarts. The monitor caches candidate PIDs between full scans of `/proc`.

## Docker

Enable Docker Manager to share its data. Under **Configure**, enter the Compose project names as a comma-separated list. If Docker Manager reports a valid local Compose directory, **Import Compose** can register it directly. A Compose name belongs to one project at a time.

The monitor reports container metrics separately from local process metrics. It marks totals as partial when Docker only supplies metadata. Authenticate through Docker Manager. If you installed an older privileged helper, update it using the instructions in the [Docker Manager section](../README.md#docker-manager) to receive service names, project folders, and health status.

## Running project commands

Orla discovers package.json scripts, simple Makefile targets, justfile recipes, Taskfile tasks, and Compose services. For JavaScript projects, the `packageManager` field takes precedence over lockfiles. Taskfile and Compose discovery use **PyYAML** (`python-yaml` on Arch). Make sure the command is on the systemd user service's PATH.

1. Open a project in **Project Commands** and click **Run** on a discovered command. Click **Edit** to configure it.
2. Enter the executable and arguments as a list, such as `["python", "-m", "http.server", "8000"]`. Edit the source file to change discovered arguments. The working directory must be inside the project.
3. Under **Readiness, dependencies, and environment**, use `depends` to reference command IDs shown in the list. **Run** includes the selected command's dependencies.
4. Configure `ready` for the service. Supported examples are `{"type":"tcp","host":"127.0.0.1","port":5432}`, `{"type":"http","url":"http://localhost:8000/health"}`, `{"type":"docker","project":"example-project","service":"db"}`, and `{"type":"process"}`. Docker readiness requires fresh Docker Manager data and a container health check. The default timeout is 120 seconds.
5. Click **Stop** on a run to stop its unit. Commands that start Docker services need access to the engine in their own execution environment.

Running commands remain supervised when you close or restart Orla. **Logs** opens the default terminal with `xdg-terminal-exec` to stream stdout and stderr. You can also search the last 150 lines per run in the panel. History keeps the latest 100 completed runs and any active runs. **Restart** replaces an active run. **Run again** uses the current command definition.

## Configuration and privacy

The registry and history live in a directory private to your account under `$XDG_STATE_HOME/orla/projects/`, normally `~/.local/state/orla/projects/`. Reference variables already in the systemd user environment with entries such as `"env":{"API_TOKEN":"DEV_API_TOKEN"}`. Orla resolves the value when the run starts. To opt in to passing a command string through a shell, specify the shell and its arguments explicitly and set `"shell":true`.

Logs redact common credential names and formats, private key blocks, and values passed by environment reference. Use `"capture":false` to suppress output from a command that might print other confidential data. Project directories, definitions, and run history stay in your account.

## Tests

Run `python tests/test_projects.py -v` in a Linux session with a systemd user manager, Node.js, and PyYAML. The suite uses temporary projects and real units and cleans up its processes. The live Docker test requires read access to the engine and at least two active Compose containers.
