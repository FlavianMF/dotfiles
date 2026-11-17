# agents/

- `AGENTS.md`: fonte única das instruções globais. O `install.sh` o linka em
  `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md` e `~/.gemini/config/AGENTS.md`.
  O `claude/CLAUDE.md` o importa com `@`.
- `docs/`: documentos que `AGENTS.md` e `claude/CLAUDE.md` apontam por ponteiro. O agente
  os lê só quando o gatilho do ponteiro dispara.
