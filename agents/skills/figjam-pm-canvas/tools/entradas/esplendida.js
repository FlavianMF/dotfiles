// ENTRADA gerada por stickies-to-entrada.mjs a partir de Esplendida/*.stickies.md. Não edite à mão: edite o .stickies.md e gere de novo.
// ===== ENTRADA ==============================================================
const S = 4.1;
const ASPECT = 1.78;
const POSTERS = [
  {
    name: "P1 · Sistema de OEE com totens",
    title: "PM Canvas — Empresa 08 — Esplendida Calçados — P1: Sistema de OEE com totens",
    md: "Esplendida/pm-canvas-empresa-08-oee-totem.md",
    stickies: {
      just: ["Produção anotada à mão", "PCP desce na linha", ["Sem refugo, OEE, Lead Time", "Sem refugo e OEE"]],
      obj: [["Reunir produção e refugo por pé", "Produção e refugo"], "Cadastrar SKU e roteiro", ["Meta: 90% turnos apontados", "Meta: 90% turnos"]],
      ben: ["Produção por etapa", "Base de refugo", "Galho e purga", "Base para OEE"],
      prod: ["Sistema web de apontar", "Totens com tablet", "Painel PCP e gerência"],
      req: [["Piloto 3 inspeções, contagem", "Piloto: 3 inspeções"], "API para P2, P3, P4", ["Offline; servidor local, nuvem", "Offline; servidor local"]],
      stk: ["§Gerente de produção", "§PCP", "§Qualidade", "§Manut. e infra", "Fornec. Senda", "UFCA"],
      eq: ["§Alunos", "§Contato, Gerente prod."],
      prem: ["Alunos fazem software", "Empresa compra tablets", "Rede da empresa", ["Offline-first", "Funciona offline"], "Senda só na fase 2", "Prazo fixo, 3 meses"],
      ent: ["Mapear no mês 1", "Cadastros e totens", "Painel e API"],
      restr: ["Sem rede na linha", "Sem histórico", "UI simples"],
      risk: ["Operador não aponta", "Base SKU falha", "Roteiro varia", "Servidor local", "Rede atrasa", "§Alunos"],
      lt: ["Mês 1: mapear, orçar", "Mês 2: MVP 3 inspeções", "Mês 3: validar, Meta 90%", "Pós: OEE, Senda"],
      cust: ["§A definir", "Orçar no mês 1"],
    },
    date: "§23/09/26\nP1 núcleo\nDentro dos 3 meses",
  },
  {
    name: "P2 · Contador de itens via câmera",
    title: "PM Canvas — Empresa 08 — Esplendida Calçados — P2: Contador de itens via câmera",
    md: "Esplendida/pm-canvas-empresa-08-contador-camera.md",
    stickies: {
      just: ["Contagem 100% manual", "Produção real oculta", ["Erro humano no apontar", "Erro humano"]],
      obj: ["Contar peças na esteira", "Modelo e cor por visão", "Enviar contagem ao P1", "Meta: erro ≤ 5% vs. manual"],
      ben: ["Contagem em tempo real", "Cruza com P1", "Estação reusada no P3"],
      prod: ["Estação de visão", "Tablet de SKU ativo", "Contagem por SKU no P1"],
      req: ["Estação modular", ["Contagem na montagem", "Contar peças"], "Modelo e cor por visão", "API com buffer local", "Hardware livre"],
      stk: ["§Gerente de produção", "§PCP", ["§Operador montagem", "§Operador da linha"], "§Manut. e infra", "UFCA"],
      eq: ["§Alunos", "§Contato, Gerente prod."],
      prem: ["Alunos fazem software", "Empresa compra hardware", "Rede da empresa", ["Offline-first", "Funciona offline"], "SKU vem do tablet", "API do P1 no mês 2"],
      ent: [["Hardware e orçamento", "Hardware e custo"], "Estação e contagem", "Modelo, cor, API do P1"],
      restr: ["Tamanho por visão difícil", ["Só montagem tem esteira", "Só uma linha tem esteira"]],
      risk: ["Luz e esteira", "Treino custoso", "SKU errado no tablet", "Compra atrasa", "API do P1"],
      lt: ["Mês 1: hardware, orçar", "Mês 2: POC contagem", "Mês 3: integrar, Meta 5%", "Pós: tamanho, estações"],
      cust: ["§A definir", "Orçar no mês 1"],
    },
    date: "§23/09/26\nP2\nDentro dos 3 meses",
  },
  {
    name: "P3 · Inspeção de qualidade via câmera e IA",
    title: "PM Canvas — Empresa 08 — Esplendida Calçados — P3: Inspeção de qualidade via câmera e IA",
    md: "Esplendida/pm-canvas-empresa-08-inspecao-ia.md",
    stickies: {
      just: ["Inspeção visual e manual", ["Cor depende de 1 pessoa", "Cor: 1 pessoa"], "Refugo sem registro"],
      obj: ["Inspeção auto com IA", "Aprova ou rejeita", "Registrar defeito no P1", "Meta: 85% igual ao inspetor"],
      ben: ["Inspeção uniforme", "Refugo por defeito", "Libera verif. de cor"],
      prod: ["Estação do P2 em inspeção", "Modelo de IA de defeitos"],
      req: ["Reusa estação do P2", "Defeitos mapeados", "Classe por pé", "Envia resultado ao P1"],
      stk: ["§Gerente de produção", "§Qualidade", "§Verif. de cores", "§PCP", "UFCA"],
      eq: ["§Alunos", "§Contato, Gerente prod."],
      prem: ["Alunos fazem software", "Empresa compra hardware", ["Offline-first", "Funciona offline"], "P2 validado", "Defeitos mapeados no mês 1"],
      ent: ["Defeitos e ponto", "Imagens e modelo", "Modo inspeção e P1"],
      restr: ["Depende de P1 e P2", "Critério subjetivo"],
      risk: ["Poucas amostras", "Tom de cor sutil", "Ponto sem esteira", "Alunos ocupados"],
      lt: ["Mês 1: mapear defeitos", ["Pós: imagens, modelo, POC", "Pós: imagens, POC"], "Pós: validar, Meta 85%"],
      cust: ["§A definir", "Orçar no mês 1"],
    },
    date: "§23/09/26\nP3 pós-mês 3\nP1 e P2 ocupam alunos",
  },
  {
    name: "P4 · Monitoramento de peso de material desperdiçado",
    title: "PM Canvas — Empresa 08 — Esplendida Calçados — P4: Monitoramento de peso de material desperdiçado",
    md: "Esplendida/pm-canvas-empresa-08-peso-desperdicio.md",
    stickies: {
      just: ["Galho e purga não medidos", "Rejeito sem registro", "Perda de material oculta"],
      obj: ["Fase A: estimar no P1", "Fase B: balança real", "Validar real vs. estimado", "Meta: ± 15% do peso real"],
      ben: ["Perda por molde e SKU", "Base p/ reusar sobra"],
      prod: ["Calcular por molde", "Balança em 1 injetora", "Painel estimado vs. real"],
      req: ["Peso do galho por molde", "Pesagem manual no mês 1", "Balança com saída de dados", "Envio ao P1, buffer local"],
      stk: ["§Gerente de produção", "§Operador injetora", "§Manut.", "Paulão, fórmulas", "§PCP", "UFCA"],
      eq: ["§Alunos", "§Contato, Gerente prod."],
      prem: ["Alunos fazem software", "Empresa compra balança", "Rede da empresa", ["Offline-first", "Funciona offline"], ["10 injetoras, parque misto", "10 injetoras"], "Prazo fixo, 3 meses"],
      ent: ["Pesar e calcular", "Balança piloto no P1", "Validação e expansão"],
      restr: ["Parque misto", "Balança exige rede"],
      risk: ["Operador não pesa", "Galho varia", "Balança cara", "Fase B tardia"],
      lt: ["Mês 1: pesar galho", "Mês 2: estimar no P1", "Mês 3: painel no P1", "Pós: balança, Meta 15%"],
      cust: ["§A definir", "Orçar no mês 1"],
    },
    date: "§23/09/26\nP4\nFase A no P1; B depois",
  },
];
const RENAME = {};
for (const n of figma.currentPage.children) if (n.type === 'SECTION' && !n.name.endsWith('(v1)')) RENAME[n.id] = n.name + ' (v1)';
const REMOVE = [];
// ============================================================================
