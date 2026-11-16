  /^\{"type":"message"/ {
    m = index($0, "\"message\":{\"role\":\"")
    if (!m) next
    r = substr($0, m + 19); r = substr(r, 1, index(r, "\"") - 1)
    if (r != "assistant") next
    t = index($0, "\"timestamp\":\"")
    if (!t || t > m) next
    ts = substr($0, t + 13); ts = substr(ts, 1, index(ts, "\"") - 1)
    if (ts !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?Z$/) next
    u = own($0, "\"usage\":{")
    if (!u) next
    s = substr($0, u)
    n = num(s, "totalTokens")
    if (n <= 0) n = num(s, "input") + num(s, "output") + num(s, "cacheRead") + num(s, "cacheWrite")
    if (n > 0) printf "%s %d\n", ts, n
  }
