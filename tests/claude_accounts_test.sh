#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$REPO_DIR/bin/claude-profile"
ZSH_ACCOUNTS="$REPO_DIR/zsh/claude-accounts.zsh"

fail=0
pass=0

assert_eq() {
    local label="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        pass=$((pass + 1))
    else
        echo "FAIL [$label]: got='$got' want='$want'" >&2
        fail=$((fail + 1))
    fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
export CLAUDE_DEFAULT_DIR="$HOME/.claude"
export CLAUDE_PROFILES_DIR="$HOME/.claude-profiles"
export CLAUDE_ACTIVE_LINK="$HOME/.claude-active"
export ECC_AUTO=0 PLUGINS_AUTO=0 SKILLS_AUTO=0
mkdir -p "$HOME/.local/bin" "$CLAUDE_DEFAULT_DIR"/{skills,hooks,agents,rules,commands,plugins} "$CLAUDE_PROFILES_DIR/work"
echo '{"model":"sonnet"}' >"$CLAUDE_DEFAULT_DIR/settings.json"
echo '# CLAUDE' >"$CLAUDE_DEFAULT_DIR/CLAUDE.md"
echo '#!/bin/sh' >"$CLAUDE_DEFAULT_DIR/statusline.sh"
echo '{"stale":true}' >"$CLAUDE_PROFILES_DIR/work/settings.json"

cat >"$tmp/stub-claude" <<'EOF'
#!/usr/bin/env bash
printf 'DIR=%s ARGS=%s\n' "${CLAUDE_CONFIG_DIR:-<unset>}" "$*"
EOF
chmod +x "$tmp/stub-claude" "$LAUNCHER"
export CLAUDE_REAL_BIN="$tmp/stub-claude"

ln -sfn "$LAUNCHER" "$tmp/claude-active"
ln -sfn "$LAUNCHER" "$tmp/claude-work"

# 1. Default without active symlink
out="$("$tmp/claude-active" -p hello)"
assert_eq "default unset" "$out" "DIR=<unset> ARGS=-p hello"

# 2. Explicit @work and -a work and @default
out="$("$LAUNCHER" @work -p hi)"
assert_eq "@work inline" "$out" "DIR=$CLAUDE_PROFILES_DIR/work ARGS=-p hi"

out="$("$LAUNCHER" -a work -p hi)"
assert_eq "-a work inline" "$out" "DIR=$CLAUDE_PROFILES_DIR/work ARGS=-p hi"

out="$("$LAUNCHER" @default -p hi)"
assert_eq "@default inline" "$out" "DIR=<unset> ARGS=-p hi"

# 3. argv0 claude-work
out="$("$tmp/claude-work" -p hi)"
assert_eq "argv0 claude-work" "$out" "DIR=$CLAUDE_PROFILES_DIR/work ARGS=-p hi"

# 4. ~/.claude-active symlink followed by claude-active
ln -sfn "$CLAUDE_PROFILES_DIR/work" "$CLAUDE_ACTIVE_LINK"
out="$("$tmp/claude-active" -p active)"
assert_eq "active symlink" "$out" "DIR=$CLAUDE_PROFILES_DIR/work ARGS=-p active"
rm -f "$CLAUDE_ACTIVE_LINK"

# 5. Missing profile fails cleanly
if "$LAUNCHER" @missing -p hi >/dev/null 2>&1; then
    echo "FAIL [missing profile]: expected non-zero exit" >&2
    fail=$((fail + 1))
else
    pass=$((pass + 1))
fi

# 6. zsh cswitch sync + cswitch switch + cstatus
if command -v zsh >/dev/null 2>&1; then
    zsh -c "
        set -e
        export DOTFILES_DIR='$REPO_DIR'
        source '$ZSH_ACCOUNTS'
        cswitch sync work >/dev/null
        test -L '$CLAUDE_PROFILES_DIR/work/settings.json'
        test -L '$CLAUDE_PROFILES_DIR/work/plugins'
        test -L '$CLAUDE_PROFILES_DIR/work/hooks'
        test -L '$HOME/.local/bin/claude-work'
        ls '$CLAUDE_PROFILES_DIR/work'/settings.json.bak.* >/dev/null
        cswitch work >/dev/null
        test -L '$HOME/.claude-active'
        cstatus | grep -q '@work'
        cswitch default >/dev/null
        test ! -e '$HOME/.claude-active'
    "
    pass=$((pass + 1))
fi

# 7. usage-limits providers/claude.js multi-profile parsing
if command -v node >/dev/null 2>&1; then
    node --input-type=module -e "
        import assert from 'node:assert/strict';
        import { parse } from '$REPO_DIR/herdr/app/mods/usage-limits/providers/claude.js';
        const multi = [
            JSON.stringify({ profile: 'default', reply: { type: 'control_response', response: { subtype: 'success', response: { subscription_type: 'Max', rate_limits: { limits: [{ kind: 'session', percent: 12, resets_at: 2000000000 }, { kind: 'weekly_all', percent: 34, resets_at: 2000000000 }] } } } } }),
            JSON.stringify({ profile: 'work', reply: { type: 'control_response', response: { subtype: 'success', response: { subscription_type: 'Pro', rate_limits: { limits: [{ kind: 'session', percent: 55, resets_at: 2000000000 }] } } } } }),
        ].join('\n');
        const rep = parse(multi, 1000);
        assert.equal(rep.status, 'ok');
        assert.equal(rep.windows.length, 3);
        assert.equal(rep.windows[0].short, 'default 5h');
        assert.equal(rep.windows[2].short, 'work 5h');
        assert.equal(rep.plan, 'Max / Pro');
        const single = JSON.stringify({ type: 'control_response', response: { subtype: 'success', response: { rate_limits: { limits: [{ kind: 'session', percent: 10, resets_at: 2000000000 }] } } } });
        const rep1 = parse(single, 1000);
        assert.equal(rep1.windows[0].short, '5h');
    "
    pass=$((pass + 1))
fi

# 8. over9k/claude-info.py syntax check
if command -v python3 >/dev/null 2>&1; then
    python3 -B -c "import ast, pathlib; ast.parse(pathlib.Path('$REPO_DIR/herdr/app/mods/over9k/claude-info.py').read_text())"
    pass=$((pass + 1))
fi

echo "claude_accounts_test: $pass passed, $fail failed"
exit "$fail"
