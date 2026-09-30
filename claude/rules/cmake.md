---
paths:
  - "**/CMakeLists.txt"
  - "**/*.cmake"
---
# CMake (regra local do dotfiles, não vem do ECC)

- Comece com `cmake_minimum_required(VERSION 3.x)` (a menor versão que o projeto realmente
  suporta) seguido de `project(... LANGUAGES C CXX)`; isso fixa as policies.
- CMake moderno, baseado em alvos: `target_include_directories`, `target_compile_definitions`,
  `target_compile_options`, `target_link_libraries` com `PUBLIC`/`PRIVATE`/`INTERFACE`
  corretos. Evite os globais `include_directories`, `add_definitions`, `link_libraries` e
  mexer em `CMAKE_CXX_FLAGS` direto.
- Padrão da linguagem por alvo: `target_compile_features(foo PUBLIC cxx_std_17)` ou
  `CMAKE_C_STANDARD`/`CMAKE_CXX_STANDARD` + `*_STANDARD_REQUIRED ON`.
- Build fora da árvore de fonte: `cmake -B build -S .` e `cmake --build build`; nunca
  gere arquivos dentro do source.
- Dependências via `find_package(... REQUIRED)` com alvos importados (`Foo::Foo`) ou
  `FetchContent` com versão/tag fixada; nada de caminho absoluto da máquina.
- Não use `file(GLOB ...)` para listar fontes sem `CONFIGURE_DEPENDS` (preferível: listar
  as fontes explicitamente).
- Opções do usuário com `option()`/cache variables documentadas; testes com
  `enable_testing()` + `add_test()` (ou `include(CTest)`), rodados com `ctest --test-dir build`.
- Em ESP-IDF, use as funções do framework (`idf_component_register`, `REQUIRES`/`PRIV_REQUIRES`)
  em vez de `add_library` cru.
