// ENTRADA gerada por stickies-to-entrada.mjs a partir de IKNET/*.stickies.md. Não edite à mão: edite o .stickies.md e gere de novo.
// ===== ENTRADA ==============================================================
const S = 4.1;
const ASPECT = 1.78;
const POSTERS = [
  {
    name: "P1 · Cooler ativo com telemetria",
    title: "PM Canvas — Empresa 05 — IKNET — P1: Cooler ativo com telemetria",
    md: "IKNET/pm-canvas-empresa-05-hardware.md",
    stickies: {
      just: [["Rack sem ar-condicionado", "Rack sem ar"], "Ambiente a 90 °C"],
      obj: ["Resfriar rack com Peltier", "Meta: < 50 °C, ≤ R$ 2.500"],
      ben: [["Alternativa ao ar-condicionado", "Opção ao ar"], "Custo menor", ["Telemetria do rack", "Dados do rack"]],
      prod: [["Cooler ativo com telemetria", "Cooler ativo com dados"]],
      req: ["Peltier 5 A, 16 V", "Controle PWM", "Sensores T, V, I, umid."],
      stk: ["§Pedro: cargo?", "§Eduardo: cargo?", "§Mario: cargo?", ["§Patrocinador", "§Quem patrocina"]],
      eq: ["§Alunos a confirmar", "§Contato IKNET"],
      prem: ["Software pelos alunos", "Hardware pela IKNET", ["Offline-first", "Funciona offline"], "Piloto: 1 gabinete"],
      ent: [["Orçamento de peças", "Custo das peças"], "Protótipo de bancada", ["Telemetria no cluster", "Dados no cluster"]],
      restr: ["§Vídeo das peças", "§Tensão: 24 V ou 48 V", "§Nº de pastilhas", "Máx. R$ 2.500"],
      risk: [["Condensação", "Água no gabinete"], "Queima de fontes", "Suporte distante"],
      lt: [["Mês 1: orçamento", "Mês 1: custo"], "Mês 2: protótipo", "Mês 3: teste térmico", "Pós: IP67, solar, Barbalha"],
      cust: ["≤ R$ 2.500 / unid.", ["§Orçamento no mês 1", "§Custo no mês 1"]],
    },
    date: "§22/09/26\nDentro dos 3 meses",
  },
  {
    name: "P2 · Verificação de entregáveis de atendimento por LLM",
    title: "PM Canvas — Empresa 05 — IKNET — P2: Verificação de entregáveis de atendimento por LLM",
    md: "IKNET/pm-canvas-empresa-05-llm.md",
    stickies: {
      just: [["Conferir entregável do técnico", "Conferir entrega do técnico"], "§Volume a definir"],
      obj: [["LLM verifica entregável", "LLM verifica entrega"], ["Dúvida: escala ao supervisor", "Dúvida: escala ao chefe"], "§Meta a definir"],
      ben: [["Menos conferência manual", "Menos checagem manual"], "§A definir"],
      prod: [["§Verificador com LLM", "§Checador com LLM"]],
      req: ["OCR de interface", "Suporte IPv6", ["Contexto de instalação", "Contexto da obra"], ["Velocidade", "Rapidez"], "§Critérios"],
      stk: ["§Pedro: cargo?", "§Eduardo: cargo?", "§Mario: cargo?", ["Supervisor de suporte", "Chefe de suporte"], ["§Patrocinador", "§Quem patrocina"]],
      eq: ["§Alunos a confirmar", "§Contato IKNET"],
      prem: ["Software pelos alunos", "§Acesso ao ERP", "§Exemplos de entregas"],
      ent: ["§A definir"],
      restr: [["§Escopo indefinido", "§Escopo?"], "§Dados do ERP", "§Infra do LLM"],
      risk: ["§A definir"],
      lt: ["§Mês 1: a definir", "§Mês 2: a definir", "§Mês 3: a definir", "§Pós: a definir"],
      cust: ["§A definir"],
    },
    date: "§22/09/26\nIdeia, sem escopo",
  },
];
const RENAME = {};
const REMOVE = [];
// ============================================================================
