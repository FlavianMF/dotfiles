    function role(s,   i) {
      i = index(s, "\"message\":{\"role\":\"")
      if (!i) return ""
      s = substr(s, i + 19)
      return substr(s, 1, index(s, "\"") - 1)
    }
    /^\{"type":"compaction"/ { tokens = 0; model = "" }
    /^\{"type":"message"/ {
      r = role($0)
      if (r == "user") calls++
      if (r != "assistant") next
      u = own($0, "\"usage\":{")
      if (!u) next
      s = substr($0, u)
      n = num(s, "input") + num(s, "cacheRead") + num(s, "cacheWrite")
      if (n <= 0) next
      tokens = n; model = ""
      i = own($0, "\"model\":\"")
      if (i) {
        s = substr($0, i + 9); s = substr(s, 1, index(s, "\"") - 1)
        if (s ~ /^[A-Za-z0-9._:\/-]+$/) model = s
      }
    }
    END {
      if (!tokens) exit 1
      printf "tokens=%d calls=%d", tokens, calls
      if (model != "") printf " model=%s", model
      printf "\n"
    }
