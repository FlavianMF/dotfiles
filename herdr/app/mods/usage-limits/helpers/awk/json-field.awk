function num(s, k,   p) {
  p = "\"" k "\":[0-9]+"
  if (!match(s, p)) return 0
  return substr(s, RSTART + length(k) + 3, RLENGTH - length(k) - 3) + 0
}
function last(s, k,   i, j) {
  j = 0
  while ((i = index(s, k)) > 0) { j += i; s = substr(s, i + 1) }
  return j
}
function own(s, k,   i, t) {
  i = last(s, k)
  if (!i) return 0
  t = substr(s, i + length(k) - 1)
  gsub(/\\./, "", t); gsub(/"[^"]*"/, "", t); gsub(/[^][{}]/, "", t)
  while (gsub(/[{][}]|[[][]]/, "", t)) ;
  return t == "}}" ? i : 0
}
