    NF {
      e = $1; d = 0
      if (i = index(e, "-")) { d = substr(e, 1, i - 1); e = substr(e, i + 1) }
      n = split(e, p, ":"); s = 0
      for (k = 1; k <= n; k++) s = s * 60 + p[k]
      print now - (d * 86400 + s)
    }
