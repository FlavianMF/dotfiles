---
paths:
  - "**/*.c"
  - "**/*.h"
---
# C (regra local do dotfiles, não vem do ECC)

`*.h` também aparece em projetos C++: se o header é incluído por arquivos `.cpp`, siga as
regras de C++ (`~/.claude/rules/ecc/cpp/`) e trate esta como complemento.

## Estilo

- Siga o padrão do projeto (`.clang-format`, `sdkconfig`/ESP-IDF style, kernel style).
  Sem padrão definido: clang-format e um estilo só por arquivo.
- Declare o padrão da linguagem no build (`-std=c11`/`c17`) e compile com
  `-Wall -Wextra -Werror` (ou o equivalente do projeto) sem silenciar warnings.
- `static` para tudo que não é API do módulo; header só expõe o que outros módulos usam.
- Include guard (`#ifndef FOO_H` / `#define FOO_H`) ou `#pragma once` se o projeto já usa.
- `const` em ponteiros de entrada que não são modificados; tipos de largura fixa
  (`uint32_t`, `size_t`) para tamanhos e registradores.

## Memória e erros

- Todo `malloc`/`calloc` tem dono claro e um `free` no mesmo caminho de erro; prefira
  alocação estática ou em pool em firmware.
- Cheque o retorno de toda função que pode falhar (`esp_err_t`, `-1`/`errno`, `NULL`) e
  propague ou trate; não ignore com `(void)` sem comentário.
- Um ponto de saída de limpeza (`goto cleanup`) é aceitável e preferível a vazamento.
- Nada de `strcpy`/`strcat`/`sprintf`/`gets`: use `snprintf`, `strlcpy` (se disponível) ou
  copie com tamanho explícito; valide índices antes de acessar buffers.
- Evite comportamento indefinido: inicialize variáveis, não faça overflow de inteiro com
  sinal, não use ponteiro depois do `free`, respeite alinhamento e `volatile` em registradores
  e variáveis compartilhadas com ISR.

## Concorrência e firmware

- Dados compartilhados entre tarefas/ISR: mutex/critical section ou atômicos; ISR curta, sem
  alocação e sem chamadas bloqueantes.
- Sem `delay`/busy-wait para sincronizar; use as primitivas do RTOS.

## Testes e análise

- Teste unitário no host quando possível (Unity, CMocka, ctest) isolando o hardware atrás de
  uma interface.
- Rode `cppcheck` ou `clang-tidy` quando estiverem configurados no projeto; sanitizers
  (`-fsanitize=address,undefined`) nos testes de host.
