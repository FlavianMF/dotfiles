# Multi-account management for Claude Code CLI
# Supports effortless profile switching, inline account execution (@profile / -a profile),
# visual statusline badges, and optional integration with cswap (claude-swap) for rate-limit tracking.

CLAUDE_PROFILES_DIR="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}"
mkdir -p "$CLAUDE_PROFILES_DIR" 2>/dev/null

# Load persistent active profile if ~/.claude-active exists
if [[ -z "$CLAUDE_CONFIG_DIR" && -L "$HOME/.claude-active" && -d "$HOME/.claude-active" ]]; then
    export CLAUDE_CONFIG_DIR="$(readlink -f "$HOME/.claude-active")"
fi

cswitch() {
    local cmd="${1:-}"
    local profiles_dir="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}"
    mkdir -p "$profiles_dir" 2>/dev/null

    local current_active=""
    if [[ -n "$CLAUDE_CONFIG_DIR" ]]; then
        current_active="$(basename "$CLAUDE_CONFIG_DIR")"
        [[ "$CLAUDE_CONFIG_DIR" == "$HOME/.claude" ]] && current_active="default"
    elif [[ -L "$HOME/.claude-active" ]]; then
        current_active="$(basename "$(readlink -f "$HOME/.claude-active")")"
    else
        current_active="default"
    fi

    case "$cmd" in
        "")
            # Interactive selection if no argument is passed
            local available=("default")
            if [[ -d "$profiles_dir" ]]; then
                for p in "$profiles_dir"/*(N/); do
                    available+=("$(basename "$p")")
                done
            fi

            echo -e "Current active profile: \033[1;35m@$current_active\033[0m"
            echo "Select profile to activate:"

            local chosen=""
            if command -v fzf >/dev/null 2>&1; then
                chosen=$(printf '%s\n' "${available[@]}" | fzf --height 40% --reverse --prompt="Claude Profile > ")
            else
                select opt in "${available[@]}" "[Cancel]"; do
                    if [[ "$opt" == "[Cancel]" || -z "$opt" ]]; then
                        return 0
                    fi
                    chosen="$opt"
                    break
                done
            fi

            [[ -z "$chosen" ]] && return 0
            cswitch "$chosen"
            ;;

        ls|list)
            echo "Available Claude profiles:"
            if [[ "$current_active" == "default" ]]; then
                echo -e "  * \033[1;32mdefault\033[0m (~/.claude)"
            else
                echo "    default (~/.claude)"
            fi

            if [[ -d "$profiles_dir" ]]; then
                for p in "$profiles_dir"/*(N/); do
                    local name="$(basename "$p")"
                    if [[ "$name" == "$current_active" ]]; then
                        echo -e "  * \033[1;35m@$name\033[0m ($p)"
                    else
                        echo "    @$name ($p)"
                    fi
                done
            fi
            ;;

        default|reset)
            unset CLAUDE_CONFIG_DIR
            rm -f "$HOME/.claude-active"
            echo -e "Switched to Claude [\033[1;32mdefault\033[0m] (~/.claude)"
            ;;

        new|add)
            local name="${2:-}"
            if [[ -z "$name" ]]; then
                read -rp "New profile name: " name
            fi
            # Strip any leading '@'
            name="${name#@}"
            if [[ -z "$name" ]]; then
                echo "Aborted: profile name cannot be empty" >&2
                return 1
            fi

            local target_dir="$profiles_dir/$name"
            if [[ -d "$target_dir" ]]; then
                echo "Profile '$name' already exists at $target_dir"
            else
                mkdir -p "$target_dir"
                # Symlink shared skills, CLAUDE.md, and copy settings from ~/.claude if available
                [[ -d "$HOME/.claude/skills" ]] && ln -sfn "$HOME/.claude/skills" "$target_dir/skills"
                [[ -f "$HOME/.claude/CLAUDE.md" ]] && ln -sfn "$HOME/.claude/CLAUDE.md" "$target_dir/CLAUDE.md"
                [[ -f "$HOME/.claude/settings.json" ]] && cp "$HOME/.claude/settings.json" "$target_dir/settings.json"
                echo "Created profile '$name' at $target_dir"
            fi

            echo "Activating '$name' and running 'claude login'..."
            cswitch "$name"
            CLAUDE_CONFIG_DIR="$target_dir" claude login
            ;;

        *)
            local profile_arg="${cmd#@}"
            local target_dir="$profiles_dir/$profile_arg"
            if [[ "$profile_arg" == "default" ]]; then
                cswitch default
                return 0
            fi

            if [[ ! -d "$target_dir" ]]; then
                echo "Profile '$profile_arg' does not exist."
                echo "Create it with: cswitch new $profile_arg"
                return 1
            fi

            export CLAUDE_CONFIG_DIR="$target_dir"
            ln -sfn "$target_dir" "$HOME/.claude-active"
            echo -e "Switched active profile to: \033[1;35m@$profile_arg\033[0m ($target_dir)"

            # If cswap is available and knows this profile, keep it in sync
            if command -v cswap >/dev/null 2>&1; then
                cswap switch "$profile_arg" 2>/dev/null || true
            fi
            ;;
    esac
}

# Alias shortcuts
alias cprofile="cswitch"
alias csw="cswitch"
alias cquota="cswap list 2>/dev/null || echo 'cswap is not installed. Install via: uv tool install claude-swap'"
alias cauto="cswap auto 2>/dev/null || echo 'cswap is not installed. Install via: uv tool install claude-swap'"

# Shortcut to run a one-off command under a specific profile without changing active shell profile
crun() {
    local profile="${1:-}"
    profile="${profile#@}"
    if [[ -z "$profile" || $# -lt 2 ]]; then
        echo "Usage: crun <profile> <claude arguments...>" >&2
        return 1
    fi
    shift
    local dir="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}/$profile"
    if [[ ! -d "$dir" ]]; then
        echo "Profile '$profile' not found in $dir" >&2
        return 1
    fi
    CLAUDE_CONFIG_DIR="$dir" claude "$@"
}

# Enhance claude wrapper to support @profile and -a/--account inline
# Intercepts before ecc-auto or standard claude
if [[ "$(whence -w claude 2>/dev/null)" == *"function"* ]]; then
    functions[_claude_pre_accounts]=$functions[claude]
    claude() {
        local target_profile=""
        if [[ "${1:-}" =~ ^@[a-zA-Z0-9_-]+$ ]]; then
            target_profile="${1#@}"
            shift
        elif [[ "${1:-}" == "-a" || "${1:-}" == "--account" ]]; then
            target_profile="${2#@}"
            shift 2
        fi

        if [[ -n "$target_profile" ]]; then
            local dir="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}/$target_profile"
            if [[ ! -d "$dir" ]]; then
                echo -e "\033[1;31m[claude-accounts] Profile '$target_profile' not found ($dir)\033[0m" >&2
                echo "Create it with: cswitch new $target_profile" >&2
                return 1
            fi
            echo -e "\033[1;35m● Claude Code Account:\033[0m \033[1;37m@$target_profile\033[0m" >&2
            printf '\033]0;claude [@%s]\007' "$target_profile"
            CLAUDE_CONFIG_DIR="$dir" _claude_pre_accounts "$@"
            local res=$?
            printf '\033]0;%s\007' "${USER:-user}@${HOST:-local}:${PWD/#$HOME/~}"
            return $res
        fi

        # If a global profile is active via ~/.claude-active or CLAUDE_CONFIG_DIR
        local active=""
        if [[ -n "$CLAUDE_CONFIG_DIR" ]]; then
            active="$(basename "$CLAUDE_CONFIG_DIR")"
            [[ "$active" == ".claude" ]] && active="default"
        elif [[ -L "$HOME/.claude-active" ]]; then
            active="$(basename "$(readlink -f "$HOME/.claude-active" 2>/dev/null)")"
        fi

        if [[ -n "$active" && "$active" != "default" ]]; then
            echo -e "\033[1;35m● Claude Code Account:\033[0m \033[1;37m@$active\033[0m" >&2
            printf '\033]0;claude [@%s]\007' "$active"
        fi

        _claude_pre_accounts "$@"
        local res=$?
        if [[ -n "$active" && "$active" != "default" ]]; then
            printf '\033]0;%s\007' "${USER:-user}@${HOST:-local}:${PWD/#$HOME/~}"
        fi
        return $res
    }
fi
