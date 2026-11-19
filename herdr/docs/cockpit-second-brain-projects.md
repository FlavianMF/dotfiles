# Cockpit × Second Brain Projects (`sb-projects`)

Design specification for integrating Obsidian Second Brain projects (`~/obsidian_vault`) into the Herdr `multiproject` layout without modifying upstream `cockpit` core files.

## 1. Goals & Scope

- **Project Launcher & Status Board** inside Herdr Desktop (`multiproject` layout).
- Reads curated projects from `~/obsidian_vault/00_META/projects/manifest.yaml` and `40_Projects/*.md` via `sb projects` (`sb projects list --json` + `sb projects scan` / `~/.local/state/second-brain/projects.json`).
- Overlays live **Herdr space status** (open/closed, git branch, agent state) and open **`over9k-todos` count** per project `checkout`.
- Supports **Launch/Focus** into a WSL Herdr space, **Inline Updates** via `sb projects update`, **Open in Obsidian**, and **Create & Init New Project**.

## 2. Architecture & Placement

- **Mod**: New custom Herdr mod at `herdr/app/mods/sb-projects/` (`mod.json`, `main.js`), deployed to `%USERPROFILE%\.config\herdr-app\mods\sb-projects` via `herdr/install-app.sh` (`make herdr-app-install`).
- **No upstream `cockpit` patches**: `cockpit` (`home.js`, `sidebar.js`) stays untouched; only `herdr/app/mods/cockpit/activity.js` (already adapted for `dotfiles`) and `herdr/app/layouts/multiproject.json` register the new tab.
- **Layout slot**:
  - Added to the right-side `panel-over9k` stack inside `panel-todo` in `herdr/app/layouts/multiproject.json` (alongside `todos` and `prompts`).
  - Added as a button in `herdr/app/mods/cockpit/activity.js` (`stack: "panel-over9k"`, `child: "sb-projects"`, `panel: "panel-todo"`).
- **WSL execution**: Uses Herdr's `exec(..., { on: "wsl" })` pattern (same model as `herdr/app/mods/over9k-todos/main.js`) to invoke `sb` and `git` on `wsl`.

## 3. Data Sources & Cross-Links

### Read path
1. **Second Brain registry**: Run `sb projects list --json` on `wsl` (and read `~/.local/state/second-brain/projects.json` when available) for:
   - Manifest fields: `slug`, `note`, `repo`, `checkout`, `branch`, `setup`, `test`, `harness`, `model`, `effort`.
   - Note frontmatter: `title`, `status` (`active|superseded|completed|archived`), `fase`, `prioridade` (`P1|P2|P3`), `proximo_passo`, `bloqueio`, `traycer_task`.
2. **Herdr live spaces**: Match `spaces()` + `agents()` + `panes()` on `wsl` against each project's `checkout` path to show open/closed state, active branch, and agent state (`working`, `blocked`, `done`, `idle`).
3. **Open To-dos**: Read `~/.local/share/over9k/todos/<slug>.md` (where `<slug>` is the `todo.sh` slug of `checkout`) to display the count of open `- [ ]` items per project.
4. **Filtering & Sorting**:
   - Filter toggle: **Active** (`status == "active"`) vs **All**.
   - Default sort: blocked/needs-attention and priority (`P1` → `P2` → `P3`), then open Herdr spaces first.

### Write path
- **Inline edits** on `proximo_passo`, `bloqueio`, `fase`, `prioridade`, and `status`:
  - Executes `sb projects update <slug> ...` on `wsl` so `vault_sync.py` remains the single safe writer into `~/obsidian_vault/40_Projects/<slug>.md`.
  - Note: verify/add `--status` support to `sb projects update` if missing (currently `sb.py` exposes `--proximo-passo`, `--bloqueio`, `--fase`, `--prioridade`).

## 4. Actions on Each Project Card

1. **Open / Launch**:
   - If a Herdr space on `wsl` already matches `checkout`: focus it (`space.select`) and bring the work area into view.
   - Otherwise: launch a new WSL space in `checkout` via `space.new` / `herdr-app do space.new --name <slug> --machine wsl --folder <checkout>` with the project's configured `harness` and `model`, pre-seeded with `proximo_passo` (plus a secondary option/modifier to open a plain shell without launching an agent).
2. **Inline Edit**: Expandable inline editor for `proximo_passo`, `bloqueio`, `fase`, `prioridade`, and `status`.
3. **Open in Obsidian**: Opens `40_Projects/<slug>.md` on Windows via `obsidian://open?vault=obsidian_vault&file=40_Projects/<slug>`.

## 5. Create & Init New Project (`+ New Project` Flow)

A collapsible form inside `sb-projects`:
- **Inputs**: `slug` / title, `checkout` path (defaulting to `~/projetos_claude/<slug>` or custom), `repo` (optional for local-only init), `branch` (default `main`), `prioridade` (`P1|P2|P3`), `harness`/`model`, and initial `proximo_passo`.
- **Execution steps on `wsl`**:
  1. `mkdir -p <checkout>` and `git -C <checkout> init -b <branch>` (if `.git` does not exist yet).
  2. Register in Second Brain via `sb projects add <slug> --repo <repo> --checkout <checkout> --branch <branch>` and set initial fields with `sb projects update <slug> --prioridade ... --proximo-passo ...` (note: make `--repo` optional or default to `local` in `sb projects add` for brand-new repos without a remote yet).
  3. Refresh state (`sb projects scan --project <slug>`).
  4. Open the new `wsl` Herdr space with `claude` (or selected `harness`), optionally seeded to run `second-brain-sync` bootstrap (`CLAUDE.md` / `PRD` / `RFC`) and `todo log on`.

## 6. Verification Plan

1. `sb projects` CLI unit tests in `~/obsidian_vault` for any new flags (`--status` on `update`, optional `--repo` on `add`).
2. `tests/herdr_layouts_test.sh` in `~/dotfiles` validating unique IDs and active stacks in `herdr/app/layouts/multiproject.json`.
3. Deploy with `make herdr-app-install` and validate the mod with `herdr-app.exe check` in Windows.
4. Smoke test in Herdr Desktop (`multiproject` layout): view projects, edit `proximo_passo`/`bloqueio`, launch existing project space, and create + init a disposable test project.
