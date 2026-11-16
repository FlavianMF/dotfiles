// Over9k's Help tab: each thing it adds as a page of its own (the navigator on
// the left picks one): a small picture of it drawn as the sidebar draws it (same
// sizes, icons and colours; made up, and nothing in it does anything, except the
// two samples Options also shows), then a few short lines on how to use it.
import { div, svg, image } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { window } from "herdr";
// The click that picks one more: Cmd on macOS, Ctrl elsewhere.
const pickClick = () => (window()?.platform === "macos" ? "Cmd+click" : "Ctrl+click");

const BOT = "mods/over9k/bot.svg", SUB = "mods/over9k/subagent.svg", CPU = "mods/over9k/cpu.svg", CLOCK = "mods/over9k/clock.svg";
const CHROME = "mods/workspace-chrome";
// Space colours, as the sidebar's (MARK).
const BLUE = "#5b8def", GREEN = "#3fae6a", ORANGE = "#e3814f", PURPLE = "#8b7cf6", TEAL = "#22a99a";

// The pages, in order: [{ part, title, el }].
export function helpTopics(view, t) {
  const dotted = (parts) => parts.flatMap((el, n) => (n ? [div().px(1).child("·"), el] : [el]));
  const logo = (name, size = 14) => (name === "pi" ? svg("icons/pi.svg").size(size).flex_none().text_color(t.foreground)
    : name === "shell" ? svg("icons/shell.svg").size(size).flex_none().text_color(t.foreground)
    : image(`icons/${name}.svg`).w(size).h(size).flex_none());
  const icon = (path, size = 12, color = t.dim) => svg(path).size(size).flex_none().text_color(color);
  const spinner = (size = 12) => svg(`${CHROME}/spinner.svg`).size(size).flex_none().text_color(t.working).spin(900);
  const dot = (color) => div().size(7).rounded(4).flex_none().bg(color);
  const wash = (c, a) => (/^#[0-9a-f]{6}$/i.test(c) ? c + a : t.raised);

  // A picture: a piece of the sidebar on its background.
  const frame = (...rows) => v_flex().flex_none().p(4).rounded(8).bg(t.chrome).border_1().border_color(t.border).text_size(13).children(rows.flat());
  // A piece of a menu (the + menu, a right-click menu).
  const menu = (...rows) => v_flex().flex_none().p(4).rounded(8).bg(t.popover).border_1().border_color(t.border).text_size(12.8).children(rows.flat());
  const menuHead = (text) => div().px(9).pt(6).pb(3).text_size(11).text_color(t.dim).child(text);
  const menuRow = (lead, text, end = null, on = false) => h_flex().h(28).px(9).gap(10).items_center().rounded(7).when(on, (el) => el.bg(t.selected))
    .when(Boolean(lead), (el) => el.child(lead)).child(div().flex_1().min_w(0).truncate().child(text))
    .when(Boolean(end), (el) => el.child(end));
  const small = (text, color = t.dim) => div().flex_none().text_size(11).text_color(color).child(text);
  const chev = (dir = "right", size = 11) => icon(`${CHROME}/chevron-${dir}.svg`, size);
  const button = (text, strong = false) => h_flex().h(20).px(6).flex_none().rounded(5).items_center().border(1).border_color(t.border)
    .text_size(11).text_color(strong ? t.foreground : t.dim).child(text);

  // The sidebar's rows.
  const computer = (name, { on = true, chips = [], bot = false } = {}) => h_flex().h(31).px(8).gap(7).items_center().text_size(11.5).text_color(t.dim)
    .child(icon(`${CHROME}/${name ? "server" : "monitor"}.svg`, 14, t.dim))
    .child(div().min_w(0).truncate().child(name ?? "This computer"))
    .child(div().size(6).rounded(3).flex_none().bg(on ? t.ansi2 : t.dim))
    .child(chev("down")).children(chips).child(div().flex_1())
    .when(bot, (el) => el.child(icon("mods/over9k/bot.svg", 13, t.dim)))
    .child(icon(`${CHROME}/plus.svg`, 12));
  const space = (name, color, { active = false, extras = [], tree = false, lit = null } = {}) => h_flex().h(tree ? 28 : 30).px(8).gap(9).items_center().rounded(8)
    .when(active, (el) => el.bg(t.selected)).when(Boolean(lit), (el) => el.bg(lit + "26"))
    .when(tree, (el) => el.pl(24).child(icon(`${CHROME}/branch.svg`, 13)))
    .child(div().flex_none().text_color(color ?? t.foreground).child(name)).children(extras);
  const gh = () => icon("mods/over9k/github.svg", 13).ml(-5);
  const notOpen = () => h_flex().h(26).mt(4).px(8).gap(7).items_center().text_size(11).text_color(t.dim).child(chev("down")).child("Not open");
  const closed = (name) => h_flex().h(30).px(8).items_center().text_color(t.muted).child(name);
  // An agent: status, logo, name; its details on the same line or (two) under it; chips at the end.
  const agent = (name, { status = null, l = "claude", info = [], chips = [], two = false, idle = false, picked = false, lit = null, pl = 4 } = {}) => {
    const details = h_flex().flex_none().items_center().text_size(11).text_color(t.dim).when(two, (el) => el.line_height("13px")).children(dotted(info));
    const label = div().min_w(0).truncate().text_size(12.5).text_color(idle ? t.muted : t.foreground).when(two, (el) => el.line_height("15px")).child(name);
    const chipEls = h_flex().flex_none().gap(5).items_center().children(chips);
    return h_flex().h(two ? 36 : 26).pl(pl).pr(8).gap(8).items_center().rounded(7)
      .when(picked, (el) => el.bg(t.accent + "38")).when(Boolean(lit), (el) => el.bg(lit + "26"))
      .child(h_flex().flex_none().gap(4).items_center()
        .child(h_flex().w(16).flex_none().justify_center().when(Boolean(status), (el) => el.child(status)))
        .child(logo(l)))
      .when(two, (el) => el.child(v_flex().flex_1().min_w(0)
        .child(h_flex().min_w(0).gap(6).items_center().child(label).child(div().flex_1()).child(chipEls))
        .when(info.length > 0, (x) => x.child(details))))
      .when(!two, (el) => el.child(v_flex().flex_1().min_w(0).child(h_flex().min_w(0).child(label)))
        .when(info.length > 0, (x) => x.child(details)).child(chipEls));
  };
  const facts = (...parts) => parts.filter(Boolean).map((p) => (typeof p === "string" ? div().child(p) : p));
  // A session footer under an agent's prompt: its logo, then the line.
  const footerLine = (l, parts) => h_flex().h(26).px(8).gap(6).items_center().text_size(11.5).text_color(t.muted)
    .child(logo(l, 13)).children(parts);
  const pct = (n) => div().text_color(n >= 80 ? t.ansi1 : n >= 50 ? t.ansi3 : t.ansi2).child(`${n}%`);
  // Something an agent started: status, its kind on the line, logo, name, details.
  const sub = (kind, text, details, { last = false, spin = false, l = null, chip = null } = {}) => h_flex().h(22).pl(10).pr(8).gap(3).items_center().text_size(12)
    .child(h_flex().w(12).pt(2).flex_none().justify_center().when(spin, (el) => el.child(spinner(10))))
    .child(v_flex().w(12).h(22).flex_none().items_center()
      .child(div().w(1.5).h(kind === SUB ? 5 : 6).flex_none().bg(t.input))
      .child(icon(kind, kind === SUB ? 12 : 9))
      .child(div().w(1.5).flex_1().when(!last, (el) => el.bg(t.input))))
    .when(Boolean(l), (el) => el.child(logo(l, 13)))
    .child(h_flex().flex_1().min_w(0).gap(6).items_center()
      .child(h_flex().flex_1().min_w(0).child(div().min_w(0).truncate().line_height("15px").text_color(t.muted).child(text)))
      .child(h_flex().flex_none().items_center().text_size(11).text_color(t.dim).children(dotted(facts(...details))))
      .when(Boolean(chip), (el) => el.child(chip)));
  // A link to another space or computer: out (icon →) where it started, in (→ icon) where it works;
  // `ssh`: over ssh, the computer's server icon after the arrow.
  const link = (color, dir, kind = BOT, ssh = false) => h_flex().flex_none().h(16).px(4).gap(3).items_center().rounded(4).bg(color + "26").text_size(10.5).text_color(color)
    .when(dir === "in", (el) => el.child("→")).child(svg(kind).size(kind === SUB ? 13 : 10).flex_none()).when(dir === "out", (el) => el.child("→"))
    .when(ssh, (el) => el.child(svg(`${CHROME}/server.svg`).size(10).flex_none()));
  const count = (parts, open = true) => h_flex().h(16).px(4).gap(3).items_center().rounded(4).bg(wash(t.foreground, "1a")).text_size(10.5).text_color(t.foreground)
    .children(parts.flatMap(([k, n], i) => (k ? [svg(k).size(k === SUB ? 13 : 10).flex_none().when(i > 0, (el) => el.ml(3)), div().child(String(n))] : [div().child(String(n))])))
    .child(svg(`${CHROME}/chevron-${open ? "down" : "right"}.svg`).size(8));
  const section = (label, color, n) => h_flex().h(26).mt(2).px(8).gap(6).items_center().text_size(11.5).text_color(t.muted)
    .child(div().size(6).rounded(3).flex_none().bg(color)).child(label).child(div().text_color(t.dim).child(String(n)));
  const filter = (agentsOn) => h_flex().h(30).px(8).gap(2).items_center().text_size(11.5)
    .child(h_flex().h(20).px(7).items_center().rounded(5).text_color(agentsOn ? t.muted : t.foreground).when(!agentsOn, (el) => el.bg(t.raised)).child("All"))
    .child(h_flex().h(20).px(7).gap(4).items_center().rounded(5).text_color(agentsOn ? t.foreground : t.muted).when(agentsOn, (el) => el.bg(t.raised))
      .child("Agents").child(div().text_color(t.dim).child("4")))
    .when(agentsOn, (el) => el.child(div().flex_1()).child(h_flex().flex_none().gap(1).p(1).rounded(5).border_1().border_color(t.border).text_size(11)
      .child(h_flex().h(18).px(6).items_center().rounded(4).text_color(t.dim).child("Space"))
      .child(h_flex().h(18).px(6).items_center().rounded(4).bg(t.raised).text_color(t.foreground).child("Status"))));
  const counts = (...parts) => h_flex().flex_none().gap(3).items_center().text_size(11.5).children(parts);

  // A line under a picture: a key (a word, a key press, a sample) then what it does.
  const key = (k) => h_flex().h(18).px(5).flex_none().rounded(4).items_center().bg(t.raised).border_1().border_color(t.border).text_size(11).text_color(t.foreground).child(k);
  const line = (lead, text) => h_flex().gap(8).items_start().text_size(12).text_color(t.muted)
    .child(h_flex().w(74).flex_none().justify_end().pt(1).child(lead))
    .child(div().flex_1().min_w(0).line_height("18px").child(text));
  const note = (text) => line(div(), text);
  // A page: the picture, then the lines under it (main.js puts the title above).
  const topic = (title, picture, lines) => ({ title, el: v_flex().flex_none().gap(12)
    .child(picture)
    .child(v_flex().gap(6).children(lines)) });
  // A part of the help: a few pages under one name (the navigator's headings).
  const part = (name, ...topics) => topics.map((x) => ({ ...x, part: name }));
  const side = (...pics) => v_flex().gap(6).children(pics.map((p, i) => (i ? h_flex().child(div().w(300).flex_none().child(p)) : p)));
  const done = t.done ?? t.accent;
  // The To-do panel's rows, a Timeline card, a usage row.
  const todoRow = (text, ticked, when = "") => h_flex().h(28).px(8).gap(8).items_center().text_size(12.5)
    .child(div().size(13).flex_none().rounded(7).border(1.5).border_color(BLUE).when(ticked, (el) => el.bg(BLUE).flex().items_center().justify_center()
      .child(svg(`${CHROME}/check.svg`).size(8).text_color(t.background))))
    .child(div().flex_1().min_w(0).truncate().text_color(ticked ? t.dim : t.foreground).when(ticked, (el) => el.line_through()).child(text))
    .when(Boolean(when), (el) => el.child(small(when)));
  const tlCard = (n, at, text, info, live) => h_flex().gap(8).px(6).py(4).items_start()
    .child(div().mt(4).size(9).flex_none().rounded(5).border_2().border_color(live ? t.working : t.border).when(live, (el) => el.bg(t.working)))
    .child(v_flex().flex_1().min_w(0).gap(2).px(9).py(6).rounded(8).bg(live ? t.raised : t.chrome)
      .child(h_flex().gap(6).text_size(10.5).text_color(t.dim).child(n).child(at))
      .child(div().text_size(12.5).text_color(t.foreground).truncate().child(text))
      .child(h_flex().text_size(11).text_color(t.dim).children(dotted(info))));
  const usageRow = (name, plan, left, n) => h_flex().h(28).px(8).gap(6).items_center().text_size(12)
    .child(div().text_color(t.muted).child(name)).child(div().px(5).py(1).rounded(4).bg(t.raised).text_size(10.5).text_color(t.accent).child(plan))
    .child(div().flex_1()).child(small(left)).child(div().w(32).flex().justify_end().child(pct(n))).child(chev());

  return [
    part("Spaces",
      topic("Your projects",
        frame(computer(null),
          space("~", null),
          space("my-app", BLUE, { active: true, extras: [gh()] }),
          space("fix-login", BLUE, { tree: true }),
          notOpen(), closed("old-site"), closed("notes")), [
          note("Every git repo in your Projects folder gets a space"),
          line(icon(`${CHROME}/branch.svg`, 13), "A worktree"),
          line(small("Not open"), "Double-click to open"),
          line(key("Right-click"), "Pin, unpin, rename"),
        ]),
      topic("Adding more",
        side(menu(menuHead("Add spaces"),
          menuRow(icon(`${CHROME}/folder-plus.svg`, 14, t.foreground), "Select manually", chev()),
          menuRow(icon(`${CHROME}/search.svg`, 14, t.foreground), "Scan", chev()),
          div().h(1).mx(4).my(5).bg(t.border),
          menuRow(icon(`${CHROME}/folder.svg`, 13), "my-app", h_flex().gap(4).child(button("Open")).child(button("Pinned", true))).text_size(12.5))), [
          line(key("+"), "On This computer, under Add spaces"),
          line(button("Open"), "Opens it now"),
          line(button("Pin"), "Keeps it in the sidebar"),
        ]),
      topic("Pin a default agent",
        side(frame(computer(null, { bot: true }), space("~", null),
            space("my-app", BLUE, { active: true, extras: [div().flex_1(), icon("mods/over9k/bot.svg", 13, t.dim), icon(`${CHROME}/plus.svg`, 12)] })),
          menu(menuRow(logo("claude"), "Claude Code", button("Pinned", true)), menuRow(logo("codex"), "Codex", button("Pin")))), [
          line(icon("mods/over9k/bot.svg", 13), "Starts the pinned agent in one click. On a space's row it shows on hover, like its +"),
          line(button("Pin"), "In any +, beside an agent: the default for that device and all its spaces. Click again to take it off"),
          line(key("Model"), "Pi is pinned by model: each of its models has a Pin here"),
          line(key("+"), "Everything else, as always"),
        ]),
      topic("Git",
        view.sample(t, view.spaceSample(t, view.opts())), [
          line(icon("mods/over9k/github.svg", 13), "Opens GitHub"),
          line(div().text_color(t.ansi3).child("4"), "Uncommitted files. Opens Changes"),
          line(h_flex().gap(4).child(div().text_color(t.ansi2).child("↑2")).child(div().text_color(t.ansi1).child("↓1")), "Push (click twice) or pull"),
          line(h_flex().gap(2).items_center().text_color(t.dim).child(icon("mods/over9k/pull-request.svg", 11)).child("3"), "Pull requests. Red if your review is wanted"),
          line(h_flex().gap(2).items_center().text_color(t.dim).child(icon("mods/over9k/issue.svg", 11)).child("2"), "Open issues, on your repos"),
          line(h_flex().gap(2).items_center().text_color(t.dim).child(icon("mods/over9k/star.svg", 11)).child("8"), "Stars, on your repos"),
        ])),

    part("Agents",
      topic("Status",
        frame(
          agent("Write the release notes", { status: dot(t.blocked), l: "codex", two: true, info: facts("gpt-5.5", "med", pct(71), "2m") }),
          agent("Tidy the CSS", { status: dot(done), l: "pi", idle: true, two: true, info: facts("Qwen3 Coder", pct(88), "1h") }),
          agent("Fix the login bug", { status: spinner(), two: true, info: facts("Opus 5.5", "high", pct(42)) })), [
          line(dot(t.blocked), "Needs you"),
          line(dot(done), "Done"),
          line(spinner(), "Working"),
          line(small("42%"), "Context used"),
          line(small("2m"), "Since its last reply"),
          line(key("Double-click"), "Rename"),
        ]),
      topic("Agents view",
        frame(filter(true),
          section("Needs you", t.blocked, 1),
          agent("Write the release notes", { status: dot(t.blocked), l: "codex", two: true, info: [div().text_color(GREEN).child("api"), ...facts("gpt-5.5", pct(71))] }),
          section("Working", t.working, 2),
          agent("Fix the login bug", { status: spinner(), two: true, info: [div().text_color(BLUE).child("my-app"), ...facts("Opus 5.5", pct(42))] }),
          agent("Check the backups", { status: spinner(), two: true, info: [div().text_color(ORANGE).child("infra"), ...facts("laptop", "Opus 5.5", pct(12))] })), [
          note("Every agent, on every computer"),
          line(key("Space"), "Grouped by space"),
          line(key("Status"), "Grouped by status"),
        ]),
      topic("What an agent starts",
        view.sample(t, view.agentSample(t, view.opts())), [
          line(icon(BOT, 11), "Agent"),
          line(icon(SUB, 11), "Subagent"),
          line(icon(CPU, 11), "Background command"),
          line(icon(CLOCK, 11), "Scheduled"),
          line(key("Click agent"), "Show or hide them"),
          line(key("Click one"), "View it"),
          line(key("Alt+click"), "View it in the side panel"),
          line(icon(`${CHROME}/x.svg`, 10, t.foreground), "Stop it (on hover)"),
        ]),
      topic("Links",
        frame(
          space("my-app", BLUE, { active: true }),
          agent("Fix the login bug", { status: spinner(), info: facts("Opus 5.5", pct(42)), chips: [count([[BOT, 1], [SUB, 1]])] }),
          sub(BOT, "Update the API", ["4m"], { spin: true, l: "claude", chip: link(PURPLE, "out") }),
          sub(SUB, "Run the tests over ssh", ["2m"], { last: true, spin: true, l: "claude", chip: link(ORANGE, "out", SUB, true) }),
          space("api", GREEN),
          agent("Update the API", { status: spinner(), info: facts("Opus 5.5", pct(18)), chips: [link(PURPLE, "in")], lit: PURPLE }),
          computer("laptop", { on: false }),
          v_flex().opacity(0.4).child(space("site", TEAL)).child(agent("Check the deploy", { idle: true, info: facts("Sonnet 5.5", pct(30)) }))), [
          line(link(PURPLE, "out"), "Works in another space"),
          line(link(PURPLE, "in"), "Started from somewhere else"),
          line(link(ORANGE, "out", SUB, true), "On another computer over ssh"),
          note("Hover one end to light up the other"),
          line(small("Faded"), "Computer offline"),
        ])),

    part("Panels",
      topic("To-do",
        frame(
          h_flex().h(28).px(8).gap(2).items_center().text_size(11.5)
            .child(h_flex().h(20).px(7).gap(4).items_center().rounded(5).bg(t.raised).child(div().text_color(BLUE).child("my-app")).child(div().text_color(t.dim).child("2")))
            .child(h_flex().h(20).px(7).gap(4).items_center().rounded(5).text_color(t.muted).child("All").child(div().text_color(t.dim).child("5")))
            .child(div().flex_1())
            .child(h_flex().px(5).py(1).gap(4).rounded(4).bg(t.raised).text_size(10.5).text_color(t.accent).child(icon("mods/over9k-todos/log.svg", 10, t.accent)).child("Log"))
            .child(h_flex().px(5).py(1).gap(4).text_size(10.5).text_color(t.dim).child(icon("mods/over9k-todos/sync.svg", 10)).child("Sync")),
          todoRow("Fix the footer on mobile", false, "today 15:00"),
          todoRow("Release notes for 2.1", false),
          h_flex().h(24).mt(2).px(8).gap(7).items_center().text_size(11).text_color(t.dim).child(chev("down")).child("Done").child(div().text_color(t.muted).child("12")),
          todoRow("Move the API keys out of the repo", true, "09:12")), [
          note("Each project's own list. Agents add and tick items too"),
          line(key("@"), "When it's due: @fri 3pm, @tomorrow, @in 2 hours"),
          line(key("#"), "Another project: #api tidy the logs"),
          line(icon(BOT, 11), "Send to this conversation or a new agent"),
          line(key(pickClick()), "Pick several: mark done, send or delete together"),
          line(small("Log"), "Agents add what you ask for in this project"),
          line(small("Sync"), "Its TODO.md follows the list"),
        ]),
      topic("Timeline",
        frame(
          tlCard("#3", "15:42", "fix the footer on mobile", [div().text_color(t.working).child("working"), ...facts("1m 12s", "↓ 4.1k tokens", "3 commands")], true),
          tlCard("#2", "15:30", "why does the build fail on ci?", facts("done 15:38", "8m", "↓ 12k tokens", "2 files"), false)), [
          note("Your prompts in the agent you're in, newest first"),
          line(key("Click"), "Read the whole prompt and the reply"),
          line(small("↓ 12k"), "Tokens it wrote, as the CLI counts them"),
          line(small("context"), "What it holds now (header)"),
        ]),
      topic("Usage",
        frame(usageRow("Claude", "Max", "2d 11h", 81), usageRow("Codex", "Plus", "12d 19h", 52), usageRow("Gemini", "Pro", "42m", 9)), [
          note("Each service's 5-hour and weekly limits, above Settings"),
          line(pct(9), "Under 50%"), line(pct(52), "From 50%"), line(pct(81), "From 80%"),
          line(key("Click"), "Every limit, and when each resets"),
          note("Claude's and Gemini's need their session footer (next page)"),
          note("Pick which show in Options › Usage"),
        ]),
      topic("Session footers",
        frame(
          footerLine("claude", [div().child("Opus 5.5 · high"), div().child("context"), pct(42), small("cache 59m"), div().child("5h"), pct(12), small("· 1h 59m"), div().child("week"), pct(83), small("· 2d 1h")]),
          footerLine("antigravity", [div().child("context"), pct(21), div().child("5h"), pct(30), small("· 1h 0m"), div().child("week"), pct(20), small("· 6d 11h")])), [
          note("The line under an agent's prompt. Agent rows, subagent rows and Usage read each agent directly: its files, or the session footer it shows"),
          line(logo("claude"), "Claude Code: Over9k's adds your 5-hour and weekly limits (or API spend) to Usage"),
          line(logo("antigravity"), "Antigravity: Over9k's adds its context to Agent rows, and Gemini's limits to Usage"),
          line(h_flex().gap(4).child(logo("codex")).child(logo("pi")), "Codex and Pi: none needed"),
          note("Turn them on in Options › Session footers. Any you set up yourself comes back when off"),
        ])),

    part("Extras",
      topic("Select several",
        side(
          frame(
            agent("Fix the login bug", { status: spinner(), picked: true }),
            agent("Tidy the CSS", { idle: true, l: "pi", picked: true }),
            agent("npm run dev", { l: "shell", idle: true }),
            agent("Write the release notes", { l: "codex", idle: true, picked: true })),
          menu(menuRow(null, "Group into one tab"), menuRow(null, "Close selected"), menuRow(null, "Unpin selected"))), [
          line(key("Shift+click"), "A range"),
          line(key(pickClick()), "One more"),
          line(key("Right-click"), "Act on them all"),
        ]),
      topic("Resume",
        side(
          menu(menuHead("Resume a session"),
            menuRow(logo("claude"), "Claude Code", h_flex().gap(10).items_center().child(small("12")).child(chev())),
            menuRow(logo("codex"), "Codex", h_flex().gap(10).items_center().child(small("4")).child(chev())),
            menuRow(logo("pi"), "Pi", h_flex().gap(10).items_center().child(small("2")).child(chev()))),
          menu(menuRow(logo("claude"), "Fix the login bug", small("my-app · 2h"), true),
            menuRow(logo("claude"), "Plan the launch", small("~ · 1d")),
            menuRow(logo("claude"), "Speed up search", small("api · 3d")))), [
          line(key("+"), "Past chats: that space's, or all of them on This computer"),
        ]),
      topic("Expired cache",
        frame(
          agent("Fix the login bug", { idle: true, two: true, status: dot(done), info: [...facts("Opus 5.5", pct(64), "1h"), div().ml(4).px(2).rounded(4).bg(t.hover).text_color(t.ansi1).child("clear + recap")] }),
          h_flex().h(18).pl(30).items_center().text_size(11).text_color(t.dim).child("↓"),
          agent("Fix the login bug", { status: spinner(), two: true, info: facts("Opus 5.5", pct(3)) })), [
          line(div().text_color(t.ansi1).child("exp."), "The next message would re-read the whole chat"),
          line(key("Click"), "Start fresh from a short recap. Much cheaper"),
        ]),
      topic("Other models",
        side(
          menu(menuHead("Start an agent"),
            menuRow(logo("claude"), "Claude Code"),
            menuRow(logo("pi"), "Pi", h_flex().h(20).px(6).gap(3).rounded(5).items_center().border(1).border_color(t.border).text_size(11).text_color(t.dim)
              .child("Model").child(svg(`${CHROME}/chevron-right.svg`).size(9)))),
          menu(menuRow(logo("pi"), "Qwen3 Coder", small("starts its server"), true), menuRow(logo("pi"), "Gemma 3")),
          h_flex().child(div().flex_1().child(frame(computer(null, { chips: [h_flex().h(18).px(5).gap(4).rounded(5).items_center().border(1).border_color(t.border).text_size(10.5).text_color(t.dim)
            .child(svg("mods/over9k/qwen.svg").size(10).text_color("#6f69f7")).child("Qwen3")] }))))), [
          line(key("Model ›"), "Pi on one of its models, local ones too (Pi's models.json)"),
          line(small("Qwen3"), "A running server. Click to stop it"),
        ]),
      topic("Hand-off",
        frame(
          space("~", null),
          agent("Can you fix the footer?", { idle: true, status: dot(done), info: facts("Opus 5.5", pct(8), "1m") }),
          space("my-app", BLUE),
          agent("Fix the footer", { status: spinner(), info: facts("Opus 5.5", pct(6)) })), [
          note("A chat outside your projects passes project work to a new agent in that project. Turn it on in Options"),
        ]),
      topic("Updates",
        side(
          frame(h_flex().h(28).px(8).gap(9).items_center().text_color(t.muted)
            .child(icon(`${CHROME}/panel-left.svg`, 14, t.muted)).child("Over9k help & options")
            .child(div().ml_auto().flex_none().px(5).py(1).rounded(4).bg(t.ansi1 + "26").text_size(10.5).text_color(t.ansi1).child("Update"))),
          v_flex().flex_none().p(10).gap(3).rounded(8).border_1().border_color(t.accent + "66").bg(t.accent + "14").text_size(12)
            .child(h_flex().gap(10).items_center().child(div().flex_1().font_semibold().text_color(t.foreground).child("Update available \u00b7 2 changes"))
              .child(h_flex().h(22).px(10).flex_none().rounded(6).items_center().bg(t.solid).text_size(11.5).text_color(t.solid_foreground).child("Update")))
            .child(div().text_color(t.muted).child("\u2022  Fix: the footer on mobile"))
            .child(div().text_color(t.muted).child("\u2022  Help: an Updates page"))), [
          line(div().flex_none().px(5).py(1).rounded(4).bg(t.ansi1 + "26").text_size(10.5).text_color(t.ansi1).child("Update"),
            "A newer Over9k where you installed it from (a git clone)"),
          line(button("Update", true), "Pulls it and installs it again. Settings and lists stay"),
          note("Turn the check off in Options \u203a Folders"),
        ])),
  ].flat();
}
