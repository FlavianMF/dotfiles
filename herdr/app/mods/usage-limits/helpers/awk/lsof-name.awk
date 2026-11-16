BEGIN { X = "0123456789abcdef" }
  NR == 1 {
    s = $0; out = ""
    while ((i = index(s, "\\")) > 0) {
      out = out substr(s, 1, i - 1); c = substr(s, i + 1, 1); h = tolower(substr(s, i + 2, 2))
      if (c == "\\") { out = out "\\\\"; s = substr(s, i + 2) }
      else if (c == "x" && h ~ /^[0-9a-f][0-9a-f]$/) {
        out = out sprintf("\\0%03o", 16 * (index(X, substr(h, 1, 1)) - 1) + index(X, substr(h, 2, 1)) - 1)
        s = substr(s, i + 4)
      } else exit 1
    }
    printf "%s", out s
  }
