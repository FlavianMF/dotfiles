---
name: second-brain-triage
description: >
  Triagem assíncrona e não supervisionada de candidatos a notas do Second Brain
  (Pilar 4: sb-nightly-triage) usando GPU local (NVIDIA RTX 5050 com llama-server e Qwen 2.5 Coder 7B).
  Lê candidatos pendentes da fila (queue.jsonl), eleva perfil de energia (pc-ctl power-mode llm-boost),
  executa inferência 100% offline via llm-batch e deposita rascunhos com frontmatter canônico
  (confidence: low) em ~/obsidian_vault/00_Inbox/. Restaura energia para balanced ao final.
  Use quando o usuário disser: "rodar triagem", "processar fila do second brain", "sb triage",
  "executar lote do second brain", "rodar lote de notas", ou quiser acompanhar/monitorar lotes de notas.
---

# Second Brain Triage (Offline GPU Batch)

Dispara, monitora e reporta lotes de triagem da fila de candidatos do cofre Obsidian (`~/obsidian_vault`) usando inferência 100% local e offline na GPU RTX 5050.

## Comandos Principais

O motor de triagem reside em `~/dotfiles/bin/sb-nightly-triage` (gerenciado por `llm-batch` e `pc-ctl`).

### 1. Diagnóstico e Fila Pendente (Dry-run)
Para verificar quantos candidatos estão na fila e estimar o tempo antes de rodar:
```bash
sb-nightly-triage --dry-run
# ou explicitando limite:
sb-nightly-triage --dry-run --limit 30
```

### 2. Disparo de Lotes
Sempre execute lotes usando ferramentas de execução assíncrona ou persistente (ex: `traycer_run_shell` ou em background):
* **Lote Curto / Piloto (5 a 10 notas, ~1 a 2 minutos):**
  ```bash
  sb-nightly-triage --limit 10
  ```
* **Lote Padrão de Janela (~30 a 50 notas, ~6 a 10 minutos):**
  ```bash
  sb-nightly-triage --limit 50
  ```
* **Lote na Bateria (Sem alterar perfil de energia):**
  ```bash
  sb-nightly-triage --limit 20 --skip-power
  ```

### 3. Acompanhamento de Execução
Durante a execução de um lote:
* Verifique o log de saída do shell ou monitore com `tail -n 20`:
  ```bash
  cat /home/flv/.traycer/commands/<epic-id>/<cmd-id>/output.log
  ```
* Verifique notas recém-criadas na pasta Inbox:
  ```bash
  ls -lt ~/obsidian_vault/00_Inbox/ | head -n 15
  ```

### 4. Ciclo de Vida e Recursos
1. **Energia:** O script eleva automaticamente para `pc-ctl power-mode llm-boost --ttl 2h`. Em caso de sucesso, falha ou interrupção (trap SIGINT/SIGTERM/EXIT), restaura imediatamente para `pc-ctl power-mode balanced`.
2. **GPU & Modelo:** Sobe o servidor `llama-server` na porta 8080 com o perfil `coder7b` (`Qwen/Qwen2.5-Coder-7B-Instruct-GGUF:Q4_K_M`), consumindo ~4.8 GB de VRAM na RTX 5050.
3. **Destino das Notas:** Todas as notas são salvas em `~/obsidian_vault/00_Inbox/<cid>-<slug>.md` com frontmatter canônico e `confidence: low`.
4. **Revisão Humana:** Após a triagem, as notas podem ser abertas no Obsidian ou revisadas visualmente via `sb review web`.
