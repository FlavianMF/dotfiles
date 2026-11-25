# Multi-account management for Claude Code CLI
# Supports profile switching, inline account execution (@profile / -a profile),
# visual statusline badges, and shared launchers for Herdr App and Cockpit.

CLAUDE_PROFILES_DIR="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}"
CLAUDE_DEFAULT_DIR="${CLAUDE_DEFAULT_DIR:-$HOME/.claude}"
mkdir -p "$CLAUDE_PROFILES_DIR" 2>/dev/null

# Load persistent active profile if ~/.claude-active exists
if [[ -z "$CLAUDE_CONFIG_DIR" && -L "$HOME/.claude-active" && -d "$HOME/.claude-active" ]]; then
    export CLAUDE_CONFIG_DIR="$(readlink -f "$HOME/.claude-active")"
fi

_claude_active_profile() {
    if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
        local name="$(basename "$CLAUDE_CONFIG_DIR")"
        [[ "$CLAUDE_CONFIG_DIR" == "$CLAUDE_DEFAULT_DIR" || "$name" == ".claude" ]] && echo "default" || echo "$name"
    elif [[ -L "$HOME/.claude-active" ]]; then
        local target="$(readlink -f "$HOME/.claude-active" 2>/dev/null)"
        local name="$(basename "$target")"
        [[ "$target" == "$CLAUDE_DEFAULT_DIR" || "$name" == ".claude" ]] && echo "default" || echo "$name"
    else
        echo "default"
    fi
}

_claude_sync_profile() {
    local target_dir="$1"
    local default_dir="${CLAUDE_DEFAULT_DIR:-$HOME/.claude}"
    local dotfiles_dir="${DOTFILES_DIR:-$HOME/dotfiles}"
    local launcher="$dotfiles_dir/bin/claude-profile"
    local profile_name="$(basename "$target_dir")"
    local stamp="$(date +%Y%m%d-%H%M%S)"

    mkdir -p "$target_dir"

    local item
    for item in CLAUDE.md statusline.sh skills hooks agents rules commands plugins; do
        if [[ -e "$default_dir/$item" || -L "$default_dir/$item" ]]; then
            ln -sfn "$default_dir/$item" "$target_dir/$item"
        fi
    done

    if [[ -e "$default_dir/settings.json" || -L "$default_dir/settings.json" ]]; then
        if [[ -f "$target_dir/settings.json" && ! -L "$target_dir/settings.json" ]]; then
            mv "$target_dir/settings.json" "$target_dir/settings.json.bak.$stamp"
        fi
        ln -sfn "$default_dir/settings.json" "$target_dir/settings.json"
    fi

    if [[ -x "$launcher" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sfn "$launcher" "$HOME/.local/bin/claude-profile"
        ln -sfn "$launcher" "$HOME/.local/bin/claude-active"
        if [[ "$profile_name" != "default" && "$profile_name" != "active" && "$profile_name" != "profile" ]]; then
            ln -sfn "$launcher" "$HOME/.local/bin/claude-$profile_name"
        fi
    fi
}

cswitch() {
    local cmd="${1:-}"
    local profiles_dir="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}"
    mkdir -p "$profiles_dir" 2>/dev/null

    local current_active="$(_claude_active_profile)"

    case "$cmd" in
        "")
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
            local def_auth="logged out"
            [[ -f "${CLAUDE_DEFAULT_DIR:-$HOME/.claude}/.credentials.json" ]] && def_auth="signed in"
            if [[ "$current_active" == "default" ]]; then
                echo -e "  * \033[1;32mdefault\033[0m (~/.claude) [$def_auth]"
            else
                echo "    default (~/.claude) [$def_auth]"
            fi

            if [[ -d "$profiles_dir" ]]; then
                for p in "$profiles_dir"/*(N/); do
                    local name="$(basename "$p")"
                    local auth="logged out"
                    [[ -f "$p/.credentials.json" ]] && auth="signed in"
                    if [[ "$name" == "$current_active" ]]; then
                        echo -e "  * \033[1;35m@$name\033[0m ($p) [$auth]"
                    else
                        echo "    @$name ($p) [$auth]"
                    fi
                done
            fi
            ;;

        default|reset)
            unset CLAUDE_CONFIG_DIR
            rm -f "$HOME/.claude-active"
            echo -e "Switched to Claude [\033[1;32mdefault\033[0m] (~/.claude)"
            ;;

        sync)
            local target="${2:-}"
            target="${target#@}"
            if [[ -n "$target" ]]; then
                local target_dir="$profiles_dir/$target"
                if [[ ! -d "$target_dir" ]]; then
                    echo "Profile '$target' not found ($target_dir)" >&2
                    return 1
                fi
                _claude_sync_profile "$target_dir"
                echo "Synced profile '@$target' ($target_dir)"
            else
                local synced=0
                for p in "$profiles_dir"/*(N/); do
                    _claude_sync_profile "$p"
                    echo "Synced profile '@$(basename "$p")' ($p)"
                    synced=$((synced + 1))
                done
                [[ $synced -eq 0 ]] && echo "No profiles found in $profiles_dir"
            fi
            ;;

        new|add)
            local name="${2:-}"
            if [[ -z "$name" ]]; then
                read -r "name?New profile name: "
            fi
            name="${name#@}"
            if [[ -z "$name" || "$name" == "default" || "$name" == "active" || "$name" == "profile" ]]; then
                echo "Aborted: invalid profile name '$name'" >&2
                return 1
            fi

            local target_dir="$profiles_dir/$name"
            if [[ -d "$target_dir" ]]; then
                echo "Profile '$name' already exists at $target_dir"
                _claude_sync_profile "$target_dir"
            else
                _claude_sync_profile "$target_dir"
                echo "Created profile '$name' at $target_dir"
            fi

            echo "Activating '$name' and running 'claude auth login'..."
            cswitch "$name"
            CLAUDE_CONFIG_DIR="$target_dir" command claude auth login
            ;;

        *)
            local profile_arg="${cmd#@}"
            if [[ "$profile_arg" == "default" ]]; then
                cswitch default
                return 0
            fi

            local target_dir="$profiles_dir/$profile_arg"
            if [[ ! -d "$target_dir" ]]; then
                echo "Profile '$profile_arg' does not exist."
                echo "Create it with: cswitch new $profile_arg"
                return 1
            fi

            export CLAUDE_CONFIG_DIR="$target_dir"
            ln -sfn "$target_dir" "$HOME/.claude-active"
            echo -e "Switched active profile to: \033[1;35m@$profile_arg\033[0m ($target_dir)"
            ;;
    esac
}

cstatus() {
    local profiles_dir="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}"
    local default_dir="${CLAUDE_DEFAULT_DIR:-$HOME/.claude}"
    local active="$(_claude_active_profile)"

    _print_profile_status() {
        local name="$1" dir="$2"
        local mark=" "
        [[ "$name" == "$active" ]] && mark="*"
        local auth="logged out"
        [[ -f "$dir/.credentials.json" ]] && auth="signed in"
        local email=""
        if [[ -f "$dir/.claude.json" ]] && command -v jq >/dev/null 2>&1; then
            email="$(jq -r '.oauthAccount.emailAddress // empty' "$dir/.claude.json" 2>/dev/null)"
        fi
        printf '  %s %-12s %-12s %s\n' "$mark" "@$name" "[$auth]" "${email:-(no email)}"
    }

    echo "Claude Code accounts:"
    _print_profile_status "default" "$default_dir"
    if [[ -d "$profiles_dir" ]]; then
        for p in "$profiles_dir"/*(N/); do
            _print_profile_status "$(basename "$p")" "$p"
        done
    fi
}

cquota() {
    local dotfiles_dir="${DOTFILES_DIR:-$HOME/dotfiles}"
    local helper="$dotfiles_dir/herdr/app/mods/usage-limits/helpers/claude-usage.sh"
    if [[ ! -x "$helper" ]]; then
        echo "Quota helper not found: $helper" >&2
        return 1
    fi
    local raw
    raw="$(bash "$helper" 2>/dev/null || true)"
    if [[ -z "$raw" ]]; then
        echo "No Claude usage data returned." >&2
        return 1
    fi
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$raw" | jq -r '
            if .profile then
                .profile as $p |
                (.reply.response.response.rate_limits // {}) as $rl |
                ($rl.limits // []) as $l |
                if ($l | length) > 0 then
                    "@\($p): " + ($l | map("\(.kind)=\(.percent)%") | join(", "))
                elif ($rl.five_hour or $rl.seven_day) then
                    "@\($p): 5h=\($rl.five_hour.utilization // "?")%, 7d=\($rl.seven_day.utilization // "?")%"
                else
                    "@\($p): no subscription limits"
                end
            else
                empty
            end'
    else
        printf '%s\n' "$raw"
    fi
}

# Alias shortcuts
alias cprofile="cswitch"
alias csw="cswitch"

# Shortcut to run a one-off command under a specific profile without changing active shell profile
crun() {
    local profile="${1:-}"
    profile="${profile#@}"
    if [[ -z "$profile" || $# -lt 2 ]]; then
        echo "Usage: crun <profile> <claude arguments...>" >&2
        return 1
    fi
    shift
    if [[ "$profile" == "default" ]]; then
        (unset CLAUDE_CONFIG_DIR; claude "$@")
        return $?
    fi
    local dir="${CLAUDE_PROFILES_DIR:-$HOME/.claude-profiles}/$profile"
    if [[ ! -d "$dir" ]]; then
        echo "Profile '$profile' not found in $dir" >&2
        return 1
    fi
    CLAUDE_CONFIG_DIR="$dir" claude "$@"
}

# Delegate claude() to bin/claude-profile when installed so zsh, Herdr App, and Cockpit behave identically.
if [[ "$(whence -w claude 2>/dev/null)" == *"function"* ]]; then
    functions[_claude_pre_accounts]=$functions[claude]
    claude() {
        local launcher="${DOTFILES_DIR:-$HOME/dotfiles}/bin/claude-profile"
        if [[ -x "$launcher" ]]; then
            "$launcher" "$@"
            return $?
        fi
        _claude_pre_accounts "$@"
    }
fi
