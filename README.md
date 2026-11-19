# Wuppa

**English** · [Svenska](README.sv.md)

<p align="center">
  <img src="assets/wuppa.svg" alt="Wuppa: Hi! I'm Wuppa." width="720">
</p>

**W**hole **U**ppa **P**uppa **P**ackage. Install Wuppa and you get the whole troupe at once:

| | | |
|---|---|---|
| **[Uppa](https://github.com/pipebreak33/uppa)** | `uppa` | keeps your PowerShell modules and Microsoft CLIs up to date |
| **[Puppa](https://github.com/pipebreak33/puppa)** | `puppa` | Microsoft 365 admin tasks in PowerShell in a few keystrokes |
| **[Muppa](https://github.com/pipebreak33/muppa)** | `muppa` | moves a computer from on-premises AD to Entra ID: a script and a checklist |
| **[Euppa](https://github.com/pipebreak33/euppa)** | `euppa` | everything in Entra ID: users, groups, devices, apps, roles and Conditional Access |
| **[Ruppa](https://github.com/pipebreak33/ruppa)** | `ruppa` | the app: every tool in one window, with buttons and forms |

Each tool is installed with its own installer, so afterwards they run standalone: `uppa`, `puppa`,
`muppa`, `euppa` and `ruppa` work exactly as if you had installed them one by one.

The `wuppa` command is a shared menu for all of them: start a tool, see what can be updated and update everything with
one key. The mascot is a W with eyes. Muppa and Euppa didn't make it into the acronym, but they get the best seats in the menu.

## Install (or update everything: run the same line again)

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/pipebreak33/wuppa/main/install.ps1 | iex
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/pipebreak33/wuppa/main/install.sh | sh
```

The installer finds (or on Windows installs) Python 3.8+, puts Wuppa in `~/.wuppa/app` and creates the command
`wuppa`. Then it runs the installers of Uppa, Puppa, Muppa, Euppa and Ruppa, so that every tool ends up exactly where it
otherwise would (`~/.uppa`, `~/.puppa`, `~/.muppa`, `~/.euppa`, `~/.ruppa`). If one tool cannot be installed, the others carry on.

| Variable | |
|---|---|
| `WUPPA_ONLY=1` | install only Wuppa |
| `WUPPA_SKIP="muppa puppa"` | skip tools |
| `WUPPA_REPO` / `WUPPA_BRANCH` | another source for Wuppa (the tools read `UPPA_REPO`, `PUPPA_REPO` and so on) |

From a local copy: `./install.sh` / `./install.ps1`. If `uppa`, `puppa`, `muppa`, `euppa` and `ruppa` are checked out next to
`wuppa`, they are installed from there.

## Uninstall

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/pipebreak33/wuppa/main/uninstall.ps1 | iex
```

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/pipebreak33/wuppa/main/uninstall.sh | sh
```

Removes the program and the `wuppa` command (and the PATH entry on Windows). Wuppa's settings in `~/.wuppa` are kept.
`WUPPA_PURGE=1` removes your data too, and `WUPPA_YES=1` skips the question.

From inside Wuppa: `wuppa uninstall` (everything), `wuppa uninstall puppa euppa` (only those), or *Uninstall…* in the menu.

If Wuppa installed the troupe, the uninstaller asks whether Uppa, Puppa, Muppa, Euppa and Ruppa should go too (each one is uninstalled with its own script, and their data is kept). `WUPPA_ALL=1` answers yes.

## Language

Every tool speaks **English** by default and **Swedish** on request. `wuppa lang sv` (or the **Language** row in the menu)
switches the whole troupe at once, and `wuppa lang en` switches back. The setting lives in `~/.truppa/config.json`,
and the installers and uninstallers follow it too.

## Commands

| | |
|---|---|
| `wuppa` | the menu |
| `wuppa status` | which tools are installed and whether they can be updated |
| `wuppa install [uppa puppa muppa euppa ruppa]` | install what is missing |
| `wuppa update [uppa puppa muppa euppa ruppa]` | update what has a newer version, and Wuppa itself |
| `wuppa uppa …` / `wuppa puppa …` / `wuppa muppa …` / `wuppa euppa …` / `wuppa ruppa …` | run a tool, everything after the name is passed on |
| `wuppa uninstall [name …]` | uninstall tools with their own scripts; without names everything, Wuppa too (`-y` answers yes). Your data is kept |
| `wuppa self-update` | update only Wuppa |
| `wuppa lang [en\|sv]` | language for the whole troupe |
| `--no-anim` | no animations (also off with `NO_COLOR` and when the output is piped) |

The menu works like the tools' own: arrow keys, digits as shortcuts, `u` update everything, `i` install what is missing, `a` uninstall,
`r` scan again and `q` quit.

## Technology

One Python file (standard library only, 3.8+), Windows, macOS and Linux. Installed versions are read with
`<tool> --version` and the latest from `VERSION` in each repo on GitHub. An update runs the tool's own
install line, so Wuppa never knows more about the tools than they do themselves.

## License

MIT
