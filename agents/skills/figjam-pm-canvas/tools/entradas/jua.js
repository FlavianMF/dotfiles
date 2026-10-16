// ENTRADA gerada por stickies-to-entrada.mjs a partir de Juá/*.stickies.md. Não edite à mão: edite o .stickies.md e gere de novo.
// ===== ENTRADA ==============================================================
const S = 4.1;
const ASPECT = 1.78;
const POSTERS = [
  {
    name: "P1 · Hardware de paradas e OEE",
    title: "PM Canvas — Empresa 01 — Juá Produtos de Limpeza — P1: Hardware de paradas e OEE",
    md: "Juá/pm-canvas-empresa-01-hardware-paradas.md",
    stickies: {
      just: [["Linha cascata: um para, todos param", "Um para, todos param"], ["Operador informa a causa hoje", "Operador informa causa"], ["Máquina parada não identificada", "Parada sem causa"]],
      obj: [["Achar máquina, hora e duração", "Achar máquina e hora"], "OEE: Disp. e Perf.", ["Meta: ≥ 95% iguais ao manual", "Meta: ≥ 95% certos"], "Erro de tempo ≤ 5 s"],
      ben: ["Manut. mais rápida", ["Indicadores de paradas por máquina", "Paradas por máquina"], ["Histórico para melhoria contínua", "Histórico de paradas"], ["Contador substitui etiqueta manual", "Sem etiqueta manual"]],
      prod: ["Hardware lê sensor de porta", "Lê sensor ótico da caixa", "Publica paradas no MQTT"],
      req: ["Sensor de porta é o sinal", "1 ESP32-S3 central cabeado", "Buffer local e reenvio", ["Modo sombra antes de oficial", "Sombra antes de oficial"]],
      stk: ["Murilo, contato", "Manut., Produção, T.I."],
      eq: ["§Alunos a confirmar", "§Cargo do Murilo"],
      prem: ["ESP32-S3 já existe", "Sensor ótico já instalado", ["Juá repassa tecnologia", "Juá repassa a técnica"], "Metas de ciclo no ERP"],
      ent: [["Transferir tecnologia do sensor", "Passar a técnica do sensor"], "Sensores de porta e ESP32", "Modo sombra e OEE"],
      restr: ["WiFi instável", ["Linha comprida, cabos longos", "Cabos longos"], "1 linha, 1 ESP32"],
      risk: [["Sensor ótico pode seguir ruim", "Sensor pode falhar"], "Agenda da Juá atrasa", "Cabo inviável em pontos", ["Perda de pacote falseia tempo", "Perda de pacote"], "Laravel sem API pronta"],
      lt: [["M1: Sensores e ESP32 instalados", "M1: sensores no ar"], "M2: Modo sombra rodando", "M3: Meta ≥95%, ≤5 s", ["Pós: Qualidade, fase 2, réplica", "Pós: fase 2, réplica"]],
      cust: ["Parte de R$ 10 mil/mês", "§Divisão do Murilo"],
    },
    date: "§19/09/26\nNúcleo, dentro dos 3 meses",
  },
  {
    name: "P2 · Visão IA",
    title: "PM Canvas — Empresa 01 — Juá Produtos de Limpeza — P2: Visão IA",
    md: "Juá/pm-canvas-empresa-01-visao-ia.md",
    stickies: {
      just: [["Produto fora do padrão passa", "Fora do padrão passa"], "Inspeção hoje é humana", "Rótulo, nível, tampa"],
      obj: [["Detectar fora do padrão, sinalizar", "Detectar e sinalizar"], ["Meta: acurácia ≥ 90% por classe", "Meta: acurácia ≥ 90%"], ["Falso positivo ≤ 2% sombra", "Falso positivo ≤ 2%"]],
      ben: ["Menos defeito ao cliente", ["Histórico de não conformes", "Histórico de falhas"], "Qualidade alimenta OEE do P1"],
      prod: ["Raspberry Pi 4 e câmera", ["2 pontos na linha-modelo", "2 pontos na linha"], ["Modelo multi-classe; trigger POC", "Modelo por classes"]],
      req: [["Classes: rótulo, nível, tampa", "Rótulo, nível, tampa"], ["TFLite no RPi4; sombra antes", "TFLite no RPi4"], ["Buffer local; imagens 90 dias", "Imagens 90 dias"]],
      stk: ["Murilo, contato", "Produção, T.I., Dev."],
      eq: ["§Alunos a confirmar", "§Cargo do Murilo"],
      prem: ["RPi4 já existe", "§Câmera: compra a confirmar", "Dataset coletado em campo", "Atuador e revisão: Juá"],
      ent: ["Coletar e rotular dataset", "Pontos 1 e 2", "Validar em modo sombra", ["API de imagem e trigger POC", "API de imagem"]],
      restr: ["WiFi instável", ["Sem acelerador de IA", "Sem placa de IA"], ["~1 produto por segundo", "~1 produto por s"], ["Protocolo do atuador indefinido", "Protocolo do atuador?"]],
      risk: [["CPU pode não acompanhar", "CPU pode não dar conta"], "Acurácia baixa na fábrica", "Validação lenta, sem prazo", ["Falso alarme gera perda", "Falso alarme custa"], "§Protocolo do atuador"],
      lt: ["M1: Dataset e ponto 1", ["M2: Treino, ponto 2, sombra", "M2: treino, ponto 2"], "M3: Meta ≥90%, FP ≤2%", ["Pós: Trigger real, réplica", "Pós: réplica"]],
      cust: ["Parte de R$ 10 mil/mês", "§Divisão do Murilo", "§Câmera: compra a confirmar", ["Acelerador ~R$ 350 se preciso", "Placa de IA ~R$ 350"]],
    },
    date: "§19/09/26\nModo sombra nos 3 meses",
  },
  {
    name: "P3 · Monitoramento energético",
    title: "PM Canvas — Empresa 01 — Juá Produtos de Limpeza — P3: Monitoramento energético",
    md: "Juá/pm-canvas-empresa-01-energia.md",
    stickies: {
      just: [["Sem controle de energia por linha", "Sem controle por linha"], ["Hardware de mercado é caro", "Hardware é caro"], "Substitui projeto de estoque"],
      obj: ["Medir energia por linha", ["Equipamentos e energia reativa", "Máquinas e energia reativa"], "Hardware de baixo custo", "§Meta a definir"],
      ben: [["Mede cada equipamento", "Mede cada máquina"], "Fácil expandir às linhas", ["Indicadores para decisão", "Dados para decisão"]],
      prod: [["Dispositivo de baixo custo", "Aparelho de baixo custo"], "Consumo por linha e equip."],
      req: ["Consumo por linha", "Consumo por equip.", "Energia reativa", ["§Outros indicadores", "§Outras métricas"], "§Hardware a definir", "Buffer local e reenvio"],
      stk: ["Murilo, contato", "§Demais a confirmar"],
      eq: ["§Alunos a confirmar", "§Cargo do Murilo"],
      prem: ["Começa depois do núcleo", "Baixo custo é o desafio"],
      ent: [["§Escopo e indicadores", "§Escopo e métricas"], ["Dispositivo de baixo custo", "Aparelho de baixo custo"], "Monitorar por linha"],
      restr: ["Custo limita expansão", "WiFi instável"],
      risk: [["Custo inviabiliza expansão", "Custo trava a expansão"], ["Escopo indefinido", "Escopo em aberto"], ["Verba disputada com P1, P2", "Verba disputada"], "Núcleo atrasa o início"],
      lt: ["M1–M3: Fora do prazo", ["Pós: Escopo, protótipo, monitorar", "Pós: escopo e protótipo"], "§Meta a definir"],
      cust: ["§Divisão do Murilo", "§Hardware a orçar"],
    },
    date: "§19/09/26\nPós-mês 3, depois do núcleo",
  },
];
const RENAME = {};
for (const n of figma.currentPage.children) if (n.type === 'SECTION' && !n.name.endsWith('(v1)')) RENAME[n.id] = n.name + ' (v1)';
const REMOVE = [];
// ============================================================================
