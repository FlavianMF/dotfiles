    function days_since_1970(y, m, d) {
      if (m <= 2) { y--; m += 12 }
      return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d - 719469
    }
    {
      m = $1; f = substr($0, index($0, " ") + 1); b = f; sub(/.*\//, "", b)
      t = -1
      if (b ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
        t = days_since_1970(substr(b, 1, 4) + 0, substr(b, 6, 2) + 0, substr(b, 9, 2) + 0) * 86400 + substr(b, 12, 2) * 3600 + substr(b, 15, 2) * 60 + substr(b, 18, 2)
      if (t < start - 2 && m < start) next
      n++; any = f; at = t
      if (t >= start - 2 && t <= start + 2) { own = f; om = m; hits++ }
      else if (m > other) other = m
    }
    END {
      if (hits == 1 && (peers > 1 || other <= om)) print own
      else if (!hits && peers == 1 && n == 1 && at >= 0 && at < start) print any
    }
