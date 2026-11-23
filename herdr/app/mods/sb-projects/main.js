// Second Brain Projects panel (cockpit × sb-projects):
// Lists projects from `sb projects list --json`, enriches them with state
// (~/.local/state/second-brain/projects.json), live Herdr spaces/agents/panes,
// and Over9k open to-do counts (~/.local/share/over9k/todos/<slug>.md).
// Supports Open/Focus/Shell in WSL, Open in Obsidian, Inline Update, and + New Project.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { theme, props, exec, spaces, agents, panes, knownAgents, run, notify, setShared, window as win } from "herdr";

const PRIORITY_RANK = { P1: 0, P2: 1, P3: 2 };
const PRIORITIES = ["P1", "P2", "P3"];
const STATUSES = ["active", "paused", "blocked", "done", "archived"];
const HARNESSES = ["claude", "codex", "opencode", "agy"];

const LOADER_PY = `
import json, os, pathlib, re, subprocess

home = os.path.expanduser("~")
env = dict(os.environ)
env["PATH"] = f"{home}/.local/bin:" + env.get("PATH", "")

res = subprocess.run(["sb", "projects", "list", "--json"], capture_output=True, text=True, env=env)
if res.returncode != 0:
    print(json.dumps({"error": (res.stderr or res.stdout or f"sb exit {res.returncode}").strip()}))
    raise SystemExit(0)

try:
    projects = json.loads(res.stdout or "[]")
except Exception as exc:
    print(json.dumps({"error": f"invalid sb json: {exc}"}))
    raise SystemExit(0)

state_path = pathlib.Path(home) / ".local/state/second-brain/projects.json"
state = None
if state_path.exists():
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        state = None

xdg_data = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local/share")
todos_dir = pathlib.Path(xdg_data) / "over9k/todos"
todos = {}
todo_items = {}
if todos_dir.is_dir():
    for f in todos_dir.glob("*.md"):
        try:
            items = [
                re.sub(r"^\\s*- \\[ \\]\\s*", "", line).strip()
                for line in f.read_text(encoding="utf-8", errors="ignore").splitlines()
                if re.match(r"^\\s*- \\[ \\]\\s", line)
            ]
            todos[f.stem] = len(items)
            if items:
                todo_items[f.stem] = items[:25]
        except Exception:
            pass

print(json.dumps({"home": home, "projects": projects, "state": state, "todos": todos, "todo_items": todo_items}))
`.trim();

const NEW_PROJECT_SH = `
set -e
export PATH="$HOME/.local/bin:$PATH"
slug="$1"
raw_checkout="$2"
repo="$3"
branch="$4"
prio="$5"
harness="$6"
model="$7"
next_step="$8"
do_bootstrap="$9"

[ -n "$branch" ] || branch="main"
[ -n "$raw_checkout" ] || raw_checkout="~/projetos_claude/$slug"
case "$raw_checkout" in
  "~"|"~/") checkout="$HOME" ;;
  "~/"*) checkout="$HOME/\${raw_checkout#~/}" ;;
  *) checkout="$raw_checkout" ;;
esac

mkdir -p "$checkout"
if [ ! -d "$checkout/.git" ]; then
  git -C "$checkout" init -b "$branch" >/dev/null 2>&1 || git -C "$checkout" init >/dev/null
fi

if [ -n "$repo" ]; then
  sb projects add --slug "$slug" --title "$slug" --checkout "$checkout" --branch "$branch" --harness "$harness" --model "$model" --repo "$repo"
else
  sb projects add --slug "$slug" --title "$slug" --checkout "$checkout" --branch "$branch" --harness "$harness" --model "$model"
fi

if [ -n "$next_step" ]; then
  sb projects update "$slug" --prioridade "$prio" --proximo-passo "$next_step"
else
  sb projects update "$slug" --prioridade "$prio"
fi

sb projects scan --project "$slug" >/dev/null 2>&1 || true

if [ "$do_bootstrap" = "1" ] && command -v todo >/dev/null 2>&1; then
  (cd "$checkout" && todo log on >/dev/null 2>&1 || true)
fi

printf '%s\\n' "$checkout"
`.trim();

const UPDATE_PROJECT_SH = `
set -e
export PATH="$HOME/.local/bin:$PATH"
slug="$1"
next_step="$2"
bloqueio="$3"
fase="$4"
prio="$5"
status="$6"
harness="$7"
model="$8"

sb projects update "$slug" \\
  --proximo-passo "$next_step" \\
  --bloqueio "$bloqueio" \\
  --fase "$fase" \\
  --prioridade "$prio" \\
  --status "$status" \\
  --harness "$harness" \\
  --model "$model"

sb projects scan --project "$slug" >/dev/null 2>&1 || true
`.trim();

const normFolder = (p) => String(p ?? "").replace(/\/+$/, "");

function expandHome(p, wslHome) {
  const s = normFolder(p);
  if (!s) return "";
  if (!wslHome) return s;
  if (s === "~") return normFolder(wslHome);
  if (s.startsWith("~/")) return `${normFolder(wslHome)}/${s.slice(2)}`;
  return s;
}

function todoSlugOf(folder) {
  return normFolder(folder).replace(/[^A-Za-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function openUrl(url) {
  const platform = win()?.platform;
  if (platform === "macos") return exec("open", [url]);
  if (platform === "windows") return exec("cmd", ["/c", "start", "", url]);
  return exec("xdg-open", [url]);
}

function obsidianUrlFor(project) {
  const note = String(project?.note || `40_Projects/${project?.slug || ""}.md`).replace(/\.md$/i, "");
  return `obsidian://open?vault=obsidian_vault&file=${encodeURIComponent(note)}`;
}

function iconEl(name, size = 14, color = null) {
  const el = svg(`mods/cockpit/icons/${name}.svg`).size(size).flex_none();
  return color ? el.text_color(color) : el;
}

function agentCommand(known, harness, model, hasTask = false) {
  const target = String(harness || "claude").toLowerCase();
  const hit = known.find((a) =>
    a.installed && (
      String(a.key ?? "").toLowerCase() === target ||
      String(a.program?.key ?? "").toLowerCase() === target ||
      String(a.name ?? "").toLowerCase().includes(target)
    )
  );
  const base = Array.isArray(hit?.run) && hit.run.length ? [...hit.run] : [target];
  if (model && target === "claude" && !base.includes("--model")) {
    base.push("--model", model);
  }
  if (hasTask && target === "agy" && !base.includes("-i") && !base.includes("--prompt-interactive")) {
    base.push("-i");
  }
  return base;
}

function priorityRank(p) {
  return PRIORITY_RANK[String(p ?? "").toUpperCase()] ?? 9;
}

function relAge(iso) {
  if (!iso) return "";
  const ms = Date.now() - new Date(iso).getTime();
  if (!Number.isFinite(ms) || ms < 0) return "";
  const min = Math.floor(ms / 60000);
  if (min < 1) return "agora";
  if (min < 60) return `${min}m`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h`;
  return `${Math.floor(hr / 24)}d`;
}

export default class SbProjects extends View {
  init(p, cx) {
    this.mode = (p?.mode ?? props()?.mode) === "page" ? "page" : "panel";
    this.filter = "active"; // "active" | "all"
    this.priorityFilter = "ALL"; // "ALL" | "P1" | "P2" | "P3" | "blocked"
    this.selectedSlug = null;
    this.projects = [];
    this.stateBySlug = new Map();
    this.stateTs = null;
    this.todosBySlug = new Map();
    this.todoItemsBySlug = new Map();
    this.wslHome = "";
    this.loading = false;
    this.error = null;
    this.known = [];
    this.searchInput = InputState.new({ placeholder: "Buscar projeto, fase, próximo passo..." });

    // Inline editor state (Step 5)
    this.editingSlug = null;
    this.editSaving = false;
    this.editPriority = "P2";
    this.editStatus = "active";
    this.editHarness = "claude";
    this.editNextInput = InputState.new({ placeholder: "Próximo passo" });
    this.editBlockInput = InputState.new({ placeholder: "Bloqueio (vazio para limpar)" });
    this.editPhaseInput = InputState.new({ placeholder: "Fase (ex.: execucao, spec)" });
    this.editModelInput = InputState.new({ placeholder: "model (ex.: sonnet)" });

    // Collapsible + New Project form state (Step 6)
    this.showNew = false;
    this.creating = false;
    this.newPriority = "P2";
    this.newHarness = "claude";
    this.newBootstrap = true;
    this.newSlugInput = InputState.new({ placeholder: "slug (ex.: meu_projeto)" });
    this.newCheckoutInput = InputState.new({ placeholder: "~/projetos_claude/<slug>" });
    this.newRepoInput = InputState.new({ placeholder: "repo (opcional)" });
    this.newBranchInput = InputState.new({ placeholder: "main" });
    this.newModelInput = InputState.new({ placeholder: "sonnet" });
    this.newNextInput = InputState.new({ placeholder: "Próximo passo inicial (opcional)" });

    cx.spawn(async (cx) => {
      this.known = await knownAgents().catch(() => []);
      cx.notify();
    });
    this.refresh(cx);
    cx.timer.every(15_000, (cx) => this.refresh(cx, true));
  }

  refresh(cx, quiet = false) {
    if (this.loading) return;
    this.loading = true;
    if (!quiet) cx.notify();
    cx.spawn(async (cx) => {
      try {
        const res = await exec("python3", ["-c", LOADER_PY], { on: "wsl" });
        if (res?.code !== 0) {
          this.error = (res?.stderr || res?.stdout || `wsl exit ${res?.code ?? "?"}`).trim();
          return;
        }
        const payload = JSON.parse(res.stdout || "{}");
        if (payload.error) {
          this.error = payload.error;
          return;
        }
        this.error = null;
        this.wslHome = payload.home || this.wslHome;
        this.projects = Array.isArray(payload.projects) ? payload.projects : [];
        this.stateTs = payload.state?.ts ?? null;
        this.stateBySlug = new Map((payload.state?.projects ?? []).map((x) => [x.slug, x]));
        this.todosBySlug = new Map(Object.entries(payload.todos ?? {}));
        this.todoItemsBySlug = new Map(Object.entries(payload.todo_items ?? {}));
        this.publishBadge();
      } catch (err) {
        this.error = String(err?.message ?? err ?? "Failed to load projects");
      } finally {
        this.loading = false;
        cx.notify();
      }
    });
  }

  publishBadge() {
    const active = this.projects.filter((p) => (p.status || "active") === "active");
    const blockedCount = active.filter((p) => Boolean(String(p.bloqueio ?? "").trim())).length;
    const p1Count = active.filter((p) => String(p.prioridade || "").toUpperCase() === "P1").length;
    const count = blockedCount > 0 ? blockedCount : p1Count > 0 ? p1Count : null;
    const tone = blockedCount > 0 ? "blocked" : p1Count > 0 ? "warning" : null;
    setShared("badge.projects", count ? { count, tone } : null);
  }

  resolvedCheckout(project) {
    return expandHome(project?.checkout || "", this.wslHome);
  }

  matchingSpace(project) {
    const target = this.resolvedCheckout(project);
    if (!target) return null;
    return spaces().find((s) => (s.machine ?? "wsl") === "wsl" && expandHome(s.folder, this.wslHome) === target) ?? null;
  }

  liveAgentsFor(space) {
    if (!space) return [];
    const tabIds = new Set((space.tabs ?? []).map((t) => t.id));
    const terms = new Set(panes().filter((p) => tabIds.has(p.tab)).map((p) => p.terminal));
    return agents().filter((a) => terms.has(a.address));
  }

  visibleProjects() {
    const query = this.mode === "page" ? this.searchInput.value().trim().toLowerCase() : "";
    let list = this.filter === "active"
      ? this.projects.filter((p) => (p.status || "active") === "active")
      : [...this.projects];

    if (this.mode === "page") {
      if (this.priorityFilter === "blocked") {
        list = list.filter((p) => Boolean(String(p.bloqueio ?? "").trim()));
      } else if (this.priorityFilter !== "ALL") {
        list = list.filter((p) => String(p.prioridade || "P2").toUpperCase() === this.priorityFilter);
      }
      if (query) {
        list = list.filter((p) =>
          [p.slug, p.title, p.fase, p.proximo_passo, p.bloqueio, p.harness, p.repo]
            .some((v) => String(v ?? "").toLowerCase().includes(query)),
        );
      }
    }

    return list.sort((a, b) => {
      const ab = String(a.bloqueio ?? "").trim() ? 0 : 1;
      const bb = String(b.bloqueio ?? "").trim() ? 0 : 1;
      if (ab !== bb) return ab - bb;

      const ap = priorityRank(a.prioridade);
      const bp = priorityRank(b.prioridade);
      if (ap !== bp) return ap - bp;

      const as = this.matchingSpace(a) ? 0 : 1;
      const bs = this.matchingSpace(b) ? 0 : 1;
      if (as !== bs) return as - bs;

      return String(a.title || a.slug).localeCompare(String(b.title || b.slug));
    });
  }

  openOrLaunch(project, plainShell = false) {
    const existing = this.matchingSpace(project);
    if (existing) {
      run("space.select", { id: existing.id });
      if (this.mode === "page") run("cockpit.go:work");
      return;
    }
    const folder = this.resolvedCheckout(project) || project.checkout;
    if (!folder) {
      notify({ title: "Checkout missing", body: `${project.slug} has no checkout path`, level: "error" });
      return;
    }
    const name = project.title || project.slug;
    if (plainShell) {
      run("space.new", { name, folder, machine: "wsl" });
      if (this.mode === "page") run("cockpit.go:work");
      return;
    }
    const task = String(project.proximo_passo ?? "").trim();
    const argv = agentCommand(this.known, project.harness, project.model, Boolean(task));
    run("space.new", {
      name,
      folder,
      tab: project.harness || "agent",
      argv,
      task,
      machine: "wsl",
    });
    if (this.mode === "page") run("cockpit.go:work");
  }

  startEdit(project, cx) {
    if (this.editingSlug === project.slug) {
      this.editingSlug = null;
      cx.notify();
      return;
    }
    this.editingSlug = project.slug;
    this.editPriority = PRIORITIES.includes(String(project.prioridade).toUpperCase()) ? String(project.prioridade).toUpperCase() : "P2";
    this.editStatus = STATUSES.includes(project.status) ? project.status : "active";
    this.editHarness = String(project.harness || "claude").toLowerCase();
    this.editNextInput.set_value(project.proximo_passo ?? "", cx);
    this.editBlockInput.set_value(project.bloqueio ?? "", cx);
    this.editPhaseInput.set_value(project.fase ?? "", cx);
    this.editModelInput.set_value(project.model ?? "", cx);
    cx.notify();
  }

  setProjectHarness(project, harness, cx) {
    const prev = project.harness;
    if (String(prev || "").toLowerCase() === harness) return;
    project.harness = harness;
    if (this.editingSlug === project.slug) this.editHarness = harness;
    cx.notify();
    cx.spawn(async (cx) => {
      const res = await exec(
        "sh",
        ["-c", 'export PATH="$HOME/.local/bin:$PATH"; sb projects update "$1" --harness "$2"', "sh", project.slug, harness],
        { on: "wsl" },
      ).catch((err) => ({ code: 1, stderr: String(err?.message ?? err) }));
      if (res?.code !== 0) {
        project.harness = prev;
        notify({ title: `Erro ao trocar harness de ${project.slug}`, body: (res?.stderr || res?.stdout || "").trim(), level: "error" });
        cx.notify();
      }
    });
  }

  saveEdit(project, cx) {
    if (this.editSaving) return;
    const nextStep = this.editNextInput.value().trim();
    const bloqueio = this.editBlockInput.value().trim();
    const fase = this.editPhaseInput.value().trim();
    const model = this.editModelInput.value().trim();
    const harness = this.editHarness || "claude";
    this.editSaving = true;
    this.error = null;
    cx.notify();

    cx.spawn(async (cx) => {
      try {
        const res = await exec(
          "sh",
          ["-c", UPDATE_PROJECT_SH, "sh", project.slug, nextStep, bloqueio, fase, this.editPriority, this.editStatus, harness, model],
          { on: "wsl" },
        );
        if (res?.code !== 0) {
          this.error = (res?.stderr || res?.stdout || "sb projects update failed").trim();
          notify({ title: `Erro ao salvar ${project.slug}`, body: this.error, level: "error" });
          return;
        }
        this.editingSlug = null;
        notify({ title: "Projeto atualizado", body: project.slug, level: "info" });
        this.refresh(cx, true);
      } catch (err) {
        this.error = String(err?.message ?? err);
      } finally {
        this.editSaving = false;
        cx.notify();
      }
    });
  }

  createProject(cx) {
    if (this.creating) return;
    const slug = this.newSlugInput.value().trim();
    if (!/^[a-z0-9][a-z0-9_-]*$/.test(slug)) {
      this.error = "Slug inválido: use apenas a-z, 0-9, _ ou - (começando com letra/dígito).";
      cx.notify();
      return;
    }
    const rawCheckout = this.newCheckoutInput.value().trim() || `~/projetos_claude/${slug}`;
    const repo = this.newRepoInput.value().trim();
    const branch = this.newBranchInput.value().trim() || "main";
    const model = this.newModelInput.value().trim() || "sonnet";
    const nextStep = this.newNextInput.value().trim();

    this.creating = true;
    this.error = null;
    cx.notify();

    cx.spawn(async (cx) => {
      try {
        const res = await exec(
          "sh",
          [
            "-c",
            NEW_PROJECT_SH,
            "sh",
            slug,
            rawCheckout,
            repo,
            branch,
            this.newPriority,
            this.newHarness,
            model,
            nextStep,
            this.newBootstrap ? "1" : "0",
          ],
          { on: "wsl" },
        );
        if (res?.code !== 0) {
          this.error = (res?.stderr || res?.stdout || "Falha ao criar projeto").trim();
          notify({ title: "Erro ao criar projeto", body: this.error, level: "error" });
          return;
        }

        const resolved = normFolder((res.stdout || "").trim().split(/\r?\n/).pop() || rawCheckout);
        this.showNew = false;
        this.newSlugInput.set_value("", cx);
        this.newCheckoutInput.set_value("", cx);
        this.newRepoInput.set_value("", cx);
        this.newBranchInput.set_value("", cx);
        this.newNextInput.set_value("", cx);

        const task = this.newBootstrap
          ? `Carregue a skill second-brain-sync e faça o bootstrap deste projeto (${slug}).${nextStep ? ` Próximo passo: ${nextStep}` : ""}`
          : nextStep;
        const argv = agentCommand(this.known, this.newHarness, model, Boolean(task));
        run("space.new", {
          name: slug,
          folder: resolved,
          tab: this.newHarness,
          argv,
          task,
          machine: "wsl",
        });

        notify({ title: "Projeto criado", body: `${slug} (${resolved})`, level: "info" });
        this.refresh(cx, true);
      } catch (err) {
        this.error = String(err?.message ?? err);
      } finally {
        this.creating = false;
        cx.notify();
      }
    });
  }

  pill(label, active, onClick, t, extraColor = null) {
    return h_flex()
      .px(8)
      .py(3)
      .rounded(5)
      .border_1()
      .border_color(active ? t.accent : t.border)
      .when(active, (e) => e.bg(`${t.accent}24`))
      .text_size(11)
      .text_color(extraColor ?? (active ? t.foreground : t.muted))
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(onClick)
      .child(label);
  }

  actionBtn(id, label, iconName, onClick, t, primary = false) {
    return h_flex()
      .id(id)
      .gap(4)
      .items_center()
      .px(8)
      .py(4)
      .rounded(5)
      .border_1()
      .border_color(primary ? t.accent : t.border)
      .bg(primary ? `${t.accent}22` : t.surface)
      .text_size(11)
      .text_color(primary ? t.foreground : t.muted)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click(onClick)
      .when(Boolean(iconName), (e) => e.child(iconEl(iconName, 12)))
      .child(label);
  }

  styledInput(state, t, { fontSize = 12, leadingIcon = null } = {}) {
    return h_flex()
      .h(30)
      .px(8)
      .gap(6)
      .items_center()
      .rounded(6)
      .border_1()
      .border_color(t.border)
      .bg(t.background)
      .when(Boolean(leadingIcon), (e) => e.child(iconEl(leadingIcon, 13, t.muted)))
      .child(Input.new(state).flex_1().h_full().text_size(fontSize).text_color(t.foreground));
  }

  renderNewForm(t, cx) {
    if (!this.showNew) return null;
    return v_flex()
      .gap(8)
      .p(10)
      .rounded(7)
      .border_1()
      .border_color(t.accent)
      .bg(t.surface)
      .child(
        h_flex()
          .justify_between()
          .items_center()
          .child(div().text_size(12).font_semibold().text_color(t.foreground).child("Novo Projeto (WSL + Second Brain)"))
          .child(
            div()
              .id("sb-new-close")
              .cursor_pointer()
              .text_color(t.muted)
              .hover((s) => s.text_color(t.foreground))
              .on_click(() => { this.showNew = false; cx.notify(); })
              .child(iconEl("x", 14)),
          ),
      )
      .child(this.styledInput(this.newSlugInput, t))
      .child(this.styledInput(this.newCheckoutInput, t))
      .child(
        h_flex()
          .gap(6)
          .child(div().flex_1().child(this.styledInput(this.newRepoInput, t)))
          .child(div().w(90).child(this.styledInput(this.newBranchInput, t))),
      )
      .child(this.styledInput(this.newNextInput, t))
      .child(
        h_flex()
          .gap(6)
          .flex_wrap()
          .items_center()
          .child(div().text_size(11).text_color(t.muted).child("Prio:"))
          .children(PRIORITIES.map((p) => this.pill(p, this.newPriority === p, () => { this.newPriority = p; cx.notify(); }, t)))
          .child(div().text_size(11).text_color(t.muted).ml(6).child("Harness:"))
          .children(HARNESSES.map((h) => this.pill(h, this.newHarness === h, () => { this.newHarness = h; cx.notify(); }, t)))
          .child(div().w(80).child(this.styledInput(this.newModelInput, t, { fontSize: 11 }))),
      )
      .child(
        h_flex()
          .justify_between()
          .items_center()
          .child(
            this.pill(
              this.newBootstrap ? "✓ bootstrap + todo log" : "sem bootstrap",
              this.newBootstrap,
              () => { this.newBootstrap = !this.newBootstrap; cx.notify(); },
              t,
            ),
          )
          .child(
            this.actionBtn(
              "sb-new-submit",
              this.creating ? "Criando..." : "Criar & Abrir",
              "rocket",
              () => this.createProject(cx),
              t,
              true,
            ),
          ),
      );
  }

  renderCard(project, t, cx) {
    const state = this.stateBySlug.get(project.slug);
    const space = this.matchingSpace(project);
    const live = this.liveAgentsFor(space);
    const workingCount = live.filter((a) => a.status === "working").length;
    const checkout = this.resolvedCheckout(project);
    const openTodos = this.todosBySlug.get(todoSlugOf(checkout)) ?? 0;
    const hasBlock = Boolean(String(project.bloqueio ?? "").trim());
    const prio = String(project.prioridade || "P2").toUpperCase();
    const prioColor = prio === "P1" ? t.ansi1 : prio === "P2" ? t.ansi3 : t.muted;
    const git = state?.git;
    const isEditing = this.editingSlug === project.slug;

    return v_flex()
      .id(`sb-proj-${project.slug}`)
      .gap(6)
      .p(10)
      .rounded(7)
      .border_1()
      .border_color(hasBlock ? t.blocked : space ? t.accent : t.border)
      .bg(t.surface)
      .child(
        h_flex()
          .justify_between()
          .items_center()
          .gap(6)
          .child(
            h_flex()
              .gap(6)
              .items_center()
              .min_w(0)
              .flex_1()
              .child(
                div()
                  .text_size(13)
                  .font_semibold()
                  .text_color(t.foreground)
                  .truncate()
                  .child(project.title || project.slug),
              )
              .when(project.title && project.title !== project.slug, (e) =>
                e.child(div().text_size(11).text_color(t.dim).truncate().child(project.slug)),
              ),
          )
          .child(
            h_flex()
              .gap(4)
              .items_center()
              .flex_none()
              .child(
                div()
                  .px(5)
                  .py(1)
                  .rounded(4)
                  .border_1()
                  .border_color(prioColor)
                  .text_size(10)
                  .font_semibold()
                  .text_color(prioColor)
                  .child(prio),
              )
              .when(Boolean(project.fase), (e) =>
                e.child(
                  div()
                    .px(5)
                    .py(1)
                    .rounded(4)
                    .bg(t.hover)
                    .text_size(10)
                    .text_color(t.muted)
                    .child(project.fase),
                ),
              )
              .when(project.status && project.status !== "active", (e) =>
                e.child(
                  div()
                    .px(5)
                    .py(1)
                    .rounded(4)
                    .bg(t.hover)
                    .text_size(10)
                    .text_color(t.dim)
                    .child(project.status),
                ),
              ),
          ),
      )
      .child(
        h_flex()
          .gap(8)
          .flex_wrap()
          .items_center()
          .text_size(11)
          .text_color(t.muted)
          .when(Boolean(space), (e) =>
            e.child(
              h_flex()
                .gap(4)
                .items_center()
                .text_color(workingCount > 0 ? t.working : t.done)
                .child(div().size(7).rounded(99).bg(workingCount > 0 ? t.working : t.done))
                .child(
                  workingCount > 0
                    ? `${workingCount} working`
                    : live.length > 0
                      ? `${live.length} open`
                      : "space open",
                ),
            ),
          )
          .when(Boolean(git?.branch), (e) =>
            e.child(
              h_flex()
                .gap(3)
                .items_center()
                .child(iconEl("git-branch", 11, t.muted))
                .child(`${git.branch}${git.dirty ? "*" : ""}${git.ahead ? ` ↑${git.ahead}` : ""}${git.behind ? ` ↓${git.behind}` : ""}`),
            ),
          )
          .when(openTodos > 0, (e) => e.child(div().text_color(t.accent).child(`${openTodos} todo${openTodos > 1 ? "s" : ""}`)))
          .when(Boolean(project.harness), (e) => e.child(div().text_color(t.dim).child(`${project.harness}${project.model ? `/${project.model}` : ""}`))),
      )
      .when(hasBlock, (e) =>
        e.child(
          h_flex()
            .gap(5)
            .items_center()
            .px(7)
            .py(4)
            .rounded(5)
            .bg(`${t.blocked}22`)
            .text_size(11)
            .text_color(t.blocked)
            .child(iconEl("triangle-alert", 12, t.blocked))
            .child(project.bloqueio),
        ),
      )
      .when(Boolean(project.proximo_passo), (e) =>
        e.child(div().text_size(12).text_color(t.foreground).child(`→ ${project.proximo_passo}`)),
      )
      .child(
        h_flex()
          .gap(6)
          .flex_wrap()
          .pt(2)
          .child(
            this.actionBtn(
              `sb-open-${project.slug}`,
              space ? "Focar" : "Abrir",
              space ? "app-window" : "play",
              () => this.openOrLaunch(project, false),
              t,
              true,
            ),
          )
          .when(!space, (e) =>
            e.child(
              this.actionBtn(
                `sb-shell-${project.slug}`,
                "Shell",
                "terminal",
                () => this.openOrLaunch(project, true),
                t,
              ),
            ),
          )
          .child(
            this.actionBtn(
              `sb-obs-${project.slug}`,
              "Obsidian",
              "external",
              () => openUrl(obsidianUrlFor(project)),
              t,
            ),
          )
          .child(
            this.actionBtn(
              `sb-edit-${project.slug}`,
              isEditing ? "Fechar" : "Editar",
              "pencil",
              () => this.startEdit(project, cx),
              t,
            ),
          ),
      )
      .when(isEditing, (e) => e.child(this.renderEditForm(project, t, cx)));
  }

  renderEditForm(project, t, cx) {
    return v_flex()
      .gap(6)
      .mt(4)
      .pt(8)
      .border_t_1()
      .border_color(t.border)
      .child(this.styledInput(this.editNextInput, t))
      .child(this.styledInput(this.editBlockInput, t))
      .child(this.styledInput(this.editPhaseInput, t))
      .child(
        h_flex()
          .gap(4)
          .flex_wrap()
          .items_center()
          .child(div().text_size(11).text_color(t.muted).child("Prio:"))
          .children(PRIORITIES.map((p) => this.pill(p, this.editPriority === p, () => { this.editPriority = p; cx.notify(); }, t)))
          .child(div().text_size(11).text_color(t.muted).ml(4).child("Status:"))
          .children(STATUSES.map((s) => this.pill(s, this.editStatus === s, () => { this.editStatus = s; cx.notify(); }, t))),
      )
      .child(
        h_flex()
          .gap(4)
          .flex_wrap()
          .items_center()
          .child(div().text_size(11).text_color(t.muted).child("Harness:"))
          .children(HARNESSES.map((h) => this.pill(h, this.editHarness === h, () => { this.editHarness = h; cx.notify(); }, t)))
          .child(div().w(84).child(this.styledInput(this.editModelInput, t, { fontSize: 11 }))),
      )
      .child(
        h_flex()
          .gap(6)
          .justify_end()
          .child(this.actionBtn(`sb-cancel-${project.slug}`, "Cancelar", "x", () => { this.editingSlug = null; cx.notify(); }, t))
          .child(this.actionBtn(`sb-save-${project.slug}`, this.editSaving ? "Salvando..." : "Salvar", "check", () => this.saveEdit(project, cx), t, true)),
      );
  }

  statTile(id, label, value, toneColor, t) {
    return v_flex()
      .id(id)
      .flex_1()
      .min_w(0)
      .p(12)
      .gap(4)
      .rounded(8)
      .border_1()
      .border_color(t.border)
      .bg(t.surface)
      .child(div().text_size(11).text_color(t.muted).child(label))
      .child(div().text_size(20).font_semibold().text_color(toneColor ?? t.foreground).child(String(value)));
  }

  renderPageCard(project, selected, t, cx) {
    const state = this.stateBySlug.get(project.slug);
    const space = this.matchingSpace(project);
    const live = this.liveAgentsFor(space);
    const workingCount = live.filter((a) => a.status === "working").length;
    const checkout = this.resolvedCheckout(project);
    const openTodos = this.todosBySlug.get(todoSlugOf(checkout)) ?? 0;
    const hasBlock = Boolean(String(project.bloqueio ?? "").trim());
    const prio = String(project.prioridade || "P2").toUpperCase();
    const prioColor = prio === "P1" ? t.ansi1 : prio === "P2" ? t.ansi3 : t.muted;
    const git = state?.git;
    const isSel = selected?.slug === project.slug;

    return v_flex()
      .id(`sb-page-card-${project.slug}`)
      .gap(6)
      .p(12)
      .rounded(8)
      .border_1()
      .border_color(isSel ? t.accent : hasBlock ? t.blocked : t.border)
      .bg(isSel ? `${t.accent}14` : t.surface)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => {
        this.selectedSlug = project.slug;
        cx.notify();
      })
      .child(
        h_flex()
          .justify_between()
          .items_center()
          .gap(8)
          .child(
            h_flex()
              .gap(8)
              .items_center()
              .min_w(0)
              .flex_1()
              .child(div().text_size(14).font_semibold().text_color(t.foreground).truncate().child(project.title || project.slug))
              .when(project.title && project.title !== project.slug, (e) =>
                e.child(div().text_size(11.5).text_color(t.dim).truncate().child(project.slug)),
              ),
          )
          .child(
            h_flex()
              .gap(5)
              .items_center()
              .flex_none()
              .child(div().px(6).py(2).rounded(4).border_1().border_color(prioColor).text_size(10.5).font_semibold().text_color(prioColor).child(prio))
              .when(Boolean(project.fase), (e) => e.child(div().px(6).py(2).rounded(4).bg(t.hover).text_size(10.5).text_color(t.muted).child(project.fase)))
              .when(project.status && project.status !== "active", (e) => e.child(div().px(6).py(2).rounded(4).bg(t.hover).text_size(10.5).text_color(t.dim).child(project.status))),
          ),
      )
      .child(
        h_flex()
          .gap(10)
          .flex_wrap()
          .items_center()
          .text_size(11.5)
          .text_color(t.muted)
          .when(Boolean(space), (e) =>
            e.child(
              h_flex()
                .gap(5)
                .items_center()
                .text_color(workingCount > 0 ? t.working : t.done)
                .child(div().size(7).rounded(99).bg(workingCount > 0 ? t.working : t.done))
                .child(workingCount > 0 ? `${workingCount} working` : live.length > 0 ? `${live.length} open` : "space open"),
            ),
          )
          .when(Boolean(git?.branch), (e) =>
            e.child(
              h_flex()
                .gap(4)
                .items_center()
                .child(iconEl("git-branch", 12, t.muted))
                .child(`${git.branch}${git.dirty ? "*" : ""}${git.ahead ? ` ↑${git.ahead}` : ""}${git.behind ? ` ↓${git.behind}` : ""}`),
            ),
          )
          .when(openTodos > 0, (e) => e.child(div().text_color(t.accent).child(`${openTodos} todo${openTodos > 1 ? "s" : ""}`)))
          .when(Boolean(project.harness), (e) => e.child(div().text_color(t.dim).child(`${project.harness}${project.model ? `/${project.model}` : ""}`))),
      )
      .when(hasBlock, (e) =>
        e.child(
          h_flex()
            .gap(6)
            .items_center()
            .px(8)
            .py(4)
            .rounded(5)
            .bg(`${t.blocked}22`)
            .text_size(11.5)
            .text_color(t.blocked)
            .child(iconEl("triangle-alert", 12, t.blocked))
            .child(project.bloqueio),
        ),
      )
      .when(Boolean(project.proximo_passo), (e) =>
        e.child(div().text_size(12.5).text_color(t.foreground).child(`→ ${project.proximo_passo}`)),
      );
  }

  renderInspector(project, t, cx) {
    if (!project) {
      return v_flex()
        .flex_1()
        .p(20)
        .items_center()
        .justify_center()
        .text_size(13)
        .text_color(t.muted)
        .child("Selecione um projeto para ver os detalhes.");
    }
    const state = this.stateBySlug.get(project.slug);
    const space = this.matchingSpace(project);
    const live = this.liveAgentsFor(space);
    const checkout = this.resolvedCheckout(project);
    const todoKey = todoSlugOf(checkout);
    const openTodos = this.todosBySlug.get(todoKey) ?? 0;
    const todoItems = this.todoItemsBySlug.get(todoKey) ?? [];
    const hasBlock = Boolean(String(project.bloqueio ?? "").trim());
    const prio = String(project.prioridade || "P2").toUpperCase();
    const git = state?.git;
    const prs = Array.isArray(state?.prs) ? state.prs : [];
    const isEditing = this.editingSlug === project.slug;

    const metaRow = (label, val) =>
      val
        ? h_flex()
            .justify_between()
            .gap(8)
            .text_size(12)
            .child(div().text_color(t.muted).flex_none().child(label))
            .child(div().text_color(t.foreground).min_w(0).truncate().child(String(val)))
        : null;

    return v_flex()
      .id(`sb-inspector-${project.slug}`)
      .flex_1()
      .min_h(0)
      .overflow_y_scroll()
      .p(16)
      .gap(12)
      .rounded(8)
      .border_1()
      .border_color(t.border)
      .bg(t.surface)
      .child(
        v_flex()
          .gap(4)
          .child(
            h_flex()
              .justify_between()
              .items_center()
              .gap(8)
              .child(div().text_size(16).font_semibold().text_color(t.foreground).min_w(0).truncate().child(project.title || project.slug))
              .child(div().px(7).py(2).rounded(4).border_1().border_color(t.border).text_size(11).text_color(t.muted).child(`${prio} · ${project.status || "active"}`)),
          )
          .child(div().text_size(12).text_color(t.dim).child(`${project.slug}${project.fase ? ` · fase: ${project.fase}` : ""}`)),
      )
      .child(
        h_flex()
          .gap(6)
          .flex_wrap()
          .child(this.actionBtn(`sb-ins-open-${project.slug}`, space ? "Focar workspace" : "Abrir workspace", space ? "app-window" : "play", () => this.openOrLaunch(project, false), t, true))
          .when(!space, (e) => e.child(this.actionBtn(`sb-ins-shell-${project.slug}`, "Shell", "terminal", () => this.openOrLaunch(project, true), t)))
          .child(this.actionBtn(`sb-ins-obs-${project.slug}`, "Obsidian", "external", () => openUrl(obsidianUrlFor(project)), t))
          .child(this.actionBtn(`sb-ins-edit-${project.slug}`, isEditing ? "Fechar" : "Editar", "pencil", () => this.startEdit(project, cx), t)),
      )
      .child(
        h_flex()
          .gap(4)
          .flex_wrap()
          .items_center()
          .child(div().text_size(11).text_color(t.muted).child("Harness ao iniciar:"))
          .children(
            HARNESSES.map((h) =>
              this.pill(
                h,
                String(project.harness || "claude").toLowerCase() === h,
                () => this.setProjectHarness(project, h, cx),
                t,
              ),
            ),
          ),
      )
      .when(isEditing, (e) => e.child(this.renderEditForm(project, t, cx)))
      .when(hasBlock, (e) =>
        e.child(
          v_flex()
            .gap(4)
            .p(10)
            .rounded(6)
            .bg(`${t.blocked}22`)
            .border_1()
            .border_color(t.blocked)
            .child(div().text_size(11).font_semibold().text_color(t.blocked).child("Bloqueio"))
            .child(div().text_size(12.5).text_color(t.foreground).child(project.bloqueio)),
        ),
      )
      .when(Boolean(project.proximo_passo), (e) =>
        e.child(
          v_flex()
            .gap(4)
            .p(10)
            .rounded(6)
            .border_1()
            .border_color(t.border)
            .bg(t.background)
            .child(div().text_size(11).font_semibold().text_color(t.muted).child("Próximo passo"))
            .child(div().text_size(12.5).text_color(t.foreground).child(project.proximo_passo)),
        ),
      )
      .child(
        v_flex()
          .gap(6)
          .pt(6)
          .border_t_1()
          .border_color(t.border)
          .child(div().text_size(11.5).font_semibold().text_color(t.muted).child("Ambiente & Git"))
          .children(
            [
              metaRow("Checkout", checkout || project.checkout),
              metaRow("Repo", project.repo),
              metaRow("Harness", project.harness ? `${project.harness}${project.model ? ` / ${project.model}` : ""}` : null),
              metaRow("Branch", git?.branch ? `${git.branch}${git.dirty ? " (dirty)" : ""}${git.ahead ? ` ↑${git.ahead}` : ""}${git.behind ? ` ↓${git.behind}` : ""}` : project.branch),
              metaRow("Agents", live.length ? `${live.length} ativo(s)` : space ? "space aberto" : "fechado"),
              metaRow("Tests", state?.tests ? JSON.stringify(state.tests) : null),
            ].filter(Boolean),
          ),
      )
      .when(prs.length > 0, (e) =>
        e.child(
          v_flex()
            .gap(4)
            .pt(6)
            .border_t_1()
            .border_color(t.border)
            .child(div().text_size(11.5).font_semibold().text_color(t.muted).child(`PRs (${prs.length})`))
            .children(prs.slice(0, 5).map((pr) => div().text_size(12).text_color(t.foreground).truncate().child(`#${pr.number ?? "?"} ${pr.title ?? pr.url ?? ""}`))),
        ),
      )
      .child(
        v_flex()
          .gap(5)
          .pt(6)
          .border_t_1()
          .border_color(t.border)
          .child(div().text_size(11.5).font_semibold().text_color(t.muted).child(`Over9k To-dos (${openTodos})`))
          .when(todoItems.length === 0, (e) => e.child(div().text_size(12).text_color(t.dim).child("Nenhum to-do aberto.")))
          .children(todoItems.slice(0, 12).map((item) => div().text_size(12).text_color(t.foreground).child(`• ${item}`))),
      );
  }

  renderPage(cx) {
    const t = theme();
    const visible = this.visibleProjects();
    const selected = visible.find((p) => p.slug === this.selectedSlug) ?? visible[0] ?? null;
    const scanAge = relAge(this.stateTs);

    const activeProjects = this.projects.filter((p) => (p.status || "active") === "active");
    const blockedCount = activeProjects.filter((p) => Boolean(String(p.bloqueio ?? "").trim())).length;
    const openSpacesCount = activeProjects.filter((p) => Boolean(this.matchingSpace(p))).length;
    const totalTodosCount = activeProjects.reduce((acc, p) => acc + (this.todosBySlug.get(todoSlugOf(this.resolvedCheckout(p))) ?? 0), 0);

    return v_flex()
      .id("sb-projects-page")
      .size_full()
      .bg(t.background)
      .text_color(t.foreground)
      .child(
        h_flex()
          .h(64)
          .px(24)
          .gap(12)
          .flex_none()
          .items_center()
          .border_b_1()
          .border_color(t.border)
          .child(
            h_flex()
              .size(32)
              .rounded(8)
              .items_center()
              .justify_center()
              .border_1()
              .border_color(t.border)
              .bg(t.surface)
              .child(iconEl("folder-git", 16, t.foreground)),
          )
          .child(
            v_flex()
              .flex_1()
              .min_w(0)
              .gap(2)
              .child(div().text_size(15).font_semibold().child("Projects"))
              .child(
                div()
                  .text_size(12)
                  .text_color(t.muted)
                  .child(`Second Brain 40_Projects · ${visible.length}/${this.projects.length}${scanAge ? ` · scan ${scanAge}` : ""}`),
              ),
          )
          .child(
            h_flex()
              .gap(6)
              .items_center()
              .child(this.pill("Active", this.filter === "active", () => { this.filter = "active"; cx.notify(); }, t))
              .child(this.pill("All", this.filter === "all", () => { this.filter = "all"; cx.notify(); }, t))
              .child(this.actionBtn("sb-page-new", "+ New", null, () => { this.showNew = !this.showNew; cx.notify(); }, t, this.showNew))
              .child(this.actionBtn("sb-page-refresh", "Atualizar", "refresh-cw", () => this.refresh(cx), t)),
          ),
      )
      .child(
        v_flex()
          .flex_1()
          .min_h(0)
          .px(24)
          .py(16)
          .gap(14)
          .when(Boolean(this.error), (e) =>
            e.child(
              h_flex()
                .gap(6)
                .items_center()
                .p(8)
                .rounded(6)
                .border_1()
                .border_color(t.ansi1)
                .bg(`${t.ansi1}18`)
                .text_size(12)
                .text_color(t.ansi1)
                .child(iconEl("alert", 13, t.ansi1))
                .child(div().flex_1().child(this.error)),
            ),
          )
          .child(
            h_flex()
              .gap(12)
              .flex_none()
              .child(this.statTile("sb-stat-active", "Ativos", activeProjects.length, t.foreground, t))
              .child(this.statTile("sb-stat-blocked", "Bloqueados", blockedCount, blockedCount > 0 ? t.blocked : t.foreground, t))
              .child(this.statTile("sb-stat-spaces", "Spaces abertos", openSpacesCount, openSpacesCount > 0 ? t.done : t.foreground, t))
              .child(this.statTile("sb-stat-todos", "To-dos abertos", totalTodosCount, totalTodosCount > 0 ? t.accent : t.foreground, t)),
          )
          .child(
            h_flex()
              .gap(8)
              .items_center()
              .flex_none()
              .child(div().flex_1().min_w(0).child(this.styledInput(this.searchInput, t, { fontSize: 12.5, leadingIcon: "search" })))
              .child(this.pill("Todos", this.priorityFilter === "ALL", () => { this.priorityFilter = "ALL"; cx.notify(); }, t))
              .child(this.pill("Bloqueados", this.priorityFilter === "blocked", () => { this.priorityFilter = "blocked"; cx.notify(); }, t, t.blocked))
              .children(PRIORITIES.map((p) => this.pill(p, this.priorityFilter === p, () => { this.priorityFilter = p; cx.notify(); }, t))),
          )
          .when(this.showNew, (e) => e.child(this.renderNewForm(t, cx)))
          .child(
            h_flex()
              .flex_1()
              .min_h(0)
              .items_start()
              .gap(14)
              .child(
                v_flex()
                  .id("sb-page-list")
                  .w(0)
                  .h_full()
                  .flex_grow(3)
                  .min_w(0)
                  .min_h(0)
                  .overflow_y_scroll()
                  .gap(8)
                  .when(visible.length === 0 && !this.loading, (e) =>
                    e.child(div().p(16).text_size(12.5).text_color(t.muted).child("Nenhum projeto encontrado para o filtro atual.")),
                  )
                  .children(visible.map((p) => this.renderPageCard(p, selected, t, cx))),
              )
              .child(
                v_flex()
                  .w(0)
                  .h_full()
                  .flex_grow(2)
                  .min_w(280)
                  .min_h(0)
                  .child(this.renderInspector(selected, t, cx)),
              ),
          ),
      );
  }

  render(cx) {
    if (this.mode === "page") return this.renderPage(cx);
    return this.renderPanel(cx);
  }

  renderPanel(cx) {
    const t = theme();
    const visible = this.visibleProjects();
    const scanAge = relAge(this.stateTs);

    return v_flex()
      .size_full()
      .bg(t.background)
      .text_color(t.foreground)
      .p(10)
      .gap(8)
      .child(
        h_flex()
          .justify_between()
          .items_center()
          .gap(6)
          .child(
            h_flex()
              .gap(6)
              .items_center()
              .child(iconEl("folder-git", 15, t.accent))
              .child(div().text_size(13).font_semibold().child("Projects"))
              .child(div().text_size(11).text_color(t.dim).child(`${visible.length}/${this.projects.length}`))
              .when(Boolean(scanAge), (e) => e.child(div().text_size(10).text_color(t.dim).child(`scan ${scanAge}`))),
          )
          .child(
            h_flex()
              .gap(4)
              .items_center()
              .child(this.pill("Active", this.filter === "active", () => { this.filter = "active"; cx.notify(); }, t))
              .child(this.pill("All", this.filter === "all", () => { this.filter = "all"; cx.notify(); }, t))
              .child(this.actionBtn("sb-new-toggle", "+ New", null, () => { this.showNew = !this.showNew; cx.notify(); }, t, this.showNew))
              .child(
                div()
                  .id("sb-refresh")
                  .p(5)
                  .rounded(5)
                  .border_1()
                  .border_color(t.border)
                  .cursor_pointer()
                  .text_color(t.muted)
                  .hover((s) => s.bg(t.hover).text_color(t.foreground))
                  .tooltip("Refresh sb projects")
                  .on_click(() => this.refresh(cx))
                  .child(iconEl("refresh-cw", 12)),
              ),
          ),
      )
      .when(Boolean(this.error), (e) =>
        e.child(
          h_flex()
            .gap(6)
            .items_center()
            .p(8)
            .rounded(6)
            .border_1()
            .border_color(t.ansi1)
            .bg(`${t.ansi1}18`)
            .text_size(11)
            .text_color(t.ansi1)
            .child(iconEl("alert", 13, t.ansi1))
            .child(div().flex_1().child(this.error)),
        ),
      )
      .when(this.showNew, (e) => e.child(this.renderNewForm(t, cx)))
      .child(
        v_flex()
          .id("sb-projects-scroll")
          .flex_1()
          .min_h(0)
          .overflow_y_scroll()
          .gap(8)
          .when(visible.length === 0 && !this.loading, (e) =>
            e.child(
              div()
                .p(16)
                .text_size(12)
                .text_color(t.muted)
                .child(this.filter === "active" ? "Nenhum projeto ativo encontrado. Tente 'All' ou '+ New'." : "Nenhum projeto cadastrado em 40_Projects/."),
            ),
          )
          .children(visible.map((p) => this.renderCard(p, t, cx))),
      );
  }
}
