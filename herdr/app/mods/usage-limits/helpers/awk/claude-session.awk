      /"type":"user"/ && /"isSidechain":false/ && !/"isMeta":true/ && !/"isCompactSummary":true/ && !/"type":"tool_result"/ { calls++ }
      /"subtype":"compact_boundary"/ {
        compactions++
        pre = num($0, "preTokens"); post = num($0, "postTokens"); tokens = post
        trigger = match($0, /"trigger":"[a-z]+"/) ? substr($0, RSTART + 11, RLENGTH - 12) : ""
      }
      /"type":"assistant"/ && /"isSidechain":false/ {
        u = index($0, "\"usage\":{")
        if (u) {
          s = substr($0, u)
          i = index(s, "\"iterations\":[")
          if (i) {
            t = substr(s, i)
            while ((i = index(t, "{\"input_tokens\":")) > 0) { s = substr(t, i); t = substr(t, i + 1) }
          }
          n = num(s, "input_tokens") + num(s, "cache_creation_input_tokens") + num(s, "cache_read_input_tokens")
          if (n > 0) tokens = n
        }
      }
      END {
        if (!tokens) exit 1
        printf "tokens=%d calls=%d compactions=%d", tokens, calls, compactions
        if (compactions) printf " lastTrigger=%s lastPre=%d lastPost=%d", trigger, pre, post
        printf "\n"
      }