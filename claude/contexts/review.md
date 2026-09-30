# Modo: revisão

Sessão de revisão de código. O objetivo é achar problemas reais, não reescrever o código.

- Leia o diff inteiro (`git diff <base>...HEAD` ou o PR) antes de comentar.
- Priorize, nesta ordem: bug de correção, segurança (segredo, injeção, permissão),
  perda de dados, contrato quebrado, teste ausente para comportamento novo; estilo por
  último e só se o projeto tiver padrão documentado.
- Cada achado: `arquivo:linha`, severidade (alta/média/baixa), o problema e a correção
  sugerida em uma ou duas linhas.
- Não edite arquivos a menos que o usuário peça; revisão entrega a lista de achados.
- Termine com um veredito: aprovar, aprovar com ressalvas ou pedir mudanças.
