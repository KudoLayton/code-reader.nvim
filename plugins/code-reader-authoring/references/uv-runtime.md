# UV runtime for Python authoring tools

Use this procedure before running a Python script from this plugin. Do not install Python packages into the explained project, the plugin directory, or the user's global Python environment.

1. Run `uv --version`. Treat a command that is found on `PATH` but cannot start as unavailable.
2. If uv is unavailable, run `winget --version`. When Winget is available and the current task authorizes package installation, run:

   ```powershell
   winget install --id astral-sh.uv -e --source winget
   ```

3. Open a new shell or restart Codex, then run `uv --version` again. A stale PATH can otherwise keep a newly installed uv unavailable to the current process.
4. If Winget is unavailable, installation fails, or uv remains unavailable after restarting, do not use `pip` as a fallback. Report the failed command and ask the user to install or repair uv using [the official installation guide](https://docs.astral.sh/uv/getting-started/installation/).

Run plugin scripts in an isolated environment with `uv run --no-project`. The static-analysis bootstrap installs its pinned parser dependencies with `uv pip` into the user-local Code Reader cache.
