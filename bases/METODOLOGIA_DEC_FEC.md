# Metodologia — Índice Apagão-SP (DEC/FEC)

Documentação técnica de como o projeto calcula DEC e FEC a partir da base
processada. Gerado em 24/08/2026, após a primeira execução real de
`scripts/05_calcular_dec_fec.R` e validação contra a cartilha ARSESP.
Complementa `bases/DICIONARIO_DADOS.md` (dicionário da base bruta) e
`CLAUDE.md` (seção "Índice Apagão-SP (DEC/FEC)").

## Por que DEC/FEC, e não um índice próprio

Decisão de 23/08/2026: usar os indicadores oficiais de continuidade do setor
elétrico (PRODIST Módulo 8 da ANEEL) em vez de inventar uma fórmula composta
própria. Vantagem: credibilidade imediata (é o padrão regulatório, não
"opinião da MAF"), comparável aos limites que a própria ANEEL/ARSESP já
publicam por conjunto e por distribuidora.

## Definições oficiais (ARSESP, cartilha "Continuidade no Fornecimento de
Energia Elétrica", 2ª edição, atualizada jul/2023)

- **DEC** (Duração Equivalente de Interrupção por Unidade Consumidora): horas
  que um conjunto de UCs, em média, ficou sem energia — considerando só
  interrupções ≥3 minutos.
- **FEC** (Frequência Equivalente de Interrupção por Unidade Consumidora):
  número de interrupções que um conjunto de UCs sofreu, em média equivalente
  — mesmo corte de 3 minutos.

Fórmulas (padrão PRODIST, implementadas em `scripts/05_calcular_dec_fec.R`):

```
DEC = Σ(UCs atingidas × horas de interrupção) / total de UCs do conjunto
FEC = Σ(UCs atingidas) / total de UCs do conjunto
```

## Os dois filtros regulatórios (o que a base geral NÃO aplica)

A base principal (`bases/interrupcoes-energia-sampa-2018-2026.rds`) serve a
outros usos descritivos além do DEC/FEC, então não aplica esses dois filtros
por padrão — `scripts/05_calcular_dec_fec.R` aplica os dois antes de calcular:

1. **Duração mínima de 3 minutos** (`total >= 180`, em segundos). Achado de
   23/08/2026: a base já não tem nenhuma linha abaixo disso (a ANEEL parece
   aplicar esse corte na própria fonte) — o filtro é aplicado mesmo assim, de
   forma explícita, por completude e pra não depender desse achado se a base
   for regerada de outra fonte no futuro.
2. **Exclusão de "expurgos"** (`IdeMotivoInterrupcao == 0`). Oito categorias
   que a regulação exclui do cálculo oficial — falha do consumidor, obra
   exclusiva do consumidor, emergência (ISE), inadimplência/deficiência
   técnica, racionamento, dia crítico, alívio de carga ONS, origem externa ao
   sistema de distribuição (lista completa e códigos em
   `bases/DICIONARIO_DADOS.md`). Na prática, os únicos códigos com volume
   relevante na nossa série são 3 (emergência/ISE) e 6 (dia crítico).

**Impacto medido (execução de 24/08/2026, base já com o crosswalk
corrigido — ver "Decisão 2" abaixo):** dos 1.764.910 registros da base
processada, **185.243 (10,5%) são excluídos** pelos dois filtros combinados
antes do cálculo de DEC/FEC — quase inteiramente pelo expurgo (a base já não
tinha praticamente nada abaixo de 3 minutos). Ou seja: o DEC/FEC é calculado
sobre um subconjunto menor e mais estrito que os números descritivos gerais
do site (total de interrupções, etc.) — os dois números não são diretamente
comparáveis, e isso precisa ficar claro na peça pública.

## Nível de agregação

- **Mensal por conjunto** (`dec_fec_mensal_conjunto.rds`/`.csv`): DEC/FEC de
  cada um dos 99 conjuntos de SP capital, por mês. `NumConsumidorConjunto`
  (denominador) é estável dentro de cada combinação conjunto×ano×mês —
  checado em 23/08/2026 (9.342 combinações, todas com valor único) — por
  isso usar o primeiro valor observado no mês é seguro.
- **Mensal agregado, SP capital inteira** (`dec_fec_mensal_sp.rds`/`.csv`):
  trata o conjunto-de-conjuntos como um "conjunto só" — soma os numeradores
  direto (são aditivos por natureza) e soma `consumidores_conjunto` de cada
  conjunto uma vez por mês (não por evento). **Isso é uma média ponderada
  pelo tamanho de cada conjunto, não uma média simples dos 99 DEC/FEC
  individuais** — decisão deliberada, evita viés de Simpson (um conjunto
  pequeno com DEC alto não pesa igual a um conjunto grande).

## Validação contra a cartilha ARSESP (24/08/2026)

Comparação do nosso DEC/FEC (SP capital, calculado a partir do microdado
ANEEL) contra os valores oficiais publicados pela ARSESP para a Enel SP
**(toda a área de concessão — Grande São Paulo, não só a capital)**:

| Ano | DEC nosso (capital) | DEC oficial Enel SP (concessão inteira) | Razão | FEC nosso | FEC oficial |
|---|---|---|---|---|---|
| 2018 | 4,39h | 6,44h | 68% | 2,81 | 4,40 |
| 2019 | 4,27h | 7,18h | 59% | 2,20 | 3,71 |
| 2020 | 5,41h | 7,14h | 76% | 2,59 | 3,84 |
| 2021 | 4,78h | 7,10h | 67% | 2,44 | 3,63 |
| 2022 | 4,78h | 6,36h | 75% | 2,52 | 3,40 |

**Leitura:** o nosso número fica sistematicamente abaixo do oficial, com
razão estável (~60-75%) ano a ano, em vez de errática. Padrão esperado e
plausível — a capital (rede urbana densa) historicamente tem continuidade
melhor que a média da concessão inteira, que inclui municípios periféricos
da Grande São Paulo com rede mais esparsa. A estabilidade da razão ano a ano
é o sinal mais importante: sugere que o cálculo está captando um recorte
geográfico real e consistente, não um erro. **Não é validação exata** (não
temos o número oficial só-capital pra comparar 1:1), só checagem de ordem de
grandeza e consistência direcional.

Fonte: `raw/interrup_energia/arsesp_cartilha_continuidade_dec_fec.pdf`,
Gráfico 2 (Enel SP, 2012-2022) — PDF oficial da ANEEL/PRODIST (texto
regulatório formal) está bloqueado por Cloudflare, não baixável via script.

## Série completa calculada (24/08/2026)

DEC/FEC anual, SP capital, agregado ponderado:

| Ano | DEC | FEC |
|---|---|---|
| 2018 | 4,39 | 2,81 |
| 2019 | 4,27 | 2,20 |
| 2020 | 5,41 | 2,59 |
| 2021 | 4,78 | 2,44 |
| 2022 | 4,78 | 2,52 |
| 2023 | 5,47 | 2,64 |
| 2024 | 5,77 | 2,59 |
| 2025 | 5,69 | 3,05 |
| 2026 | 2,89* | 1,79* |

*(valores de 2020-2023 já refletem a correção completa do crosswalk, incluindo Vargem Grande — ver "Decisão 2" abaixo)*

\* **2026 é parcial (só jan-jun)** — não comparável aos outros anos sem
anualizar. Ver "Decisões pendentes" abaixo.

## Limitações conhecidas (manter sempre visíveis na peça pública)

1. **2026 parcial.** O valor anual de 2026 cobre só até junho — mostrá-lo ao
   lado dos anos completos sem selo claro de "parcial" sugeriria (falsamente)
   uma melhora grande em relação a 2025.
2. **2020-2023: 8 de 143 conjuntos (5,6%) fora da série** nesses quatro anos
   — o `IdeConjuntoUnidadeConsumidora` não existe nativamente no schema
   desses anos e foi recuperado via crosswalk nome→id a partir do shapefile
   `CONJ`; 8 conjuntos nunca tiveram correspondência (mesmos 8 em todos os 4
   anos — gap estável do shapefile, não ruído; a maioria parece mesmo ficar
   fora do município de SP). Efeito no DEC/FEC agregado: provavelmente
   pequeno (a métrica é uma média ponderada, perder ~5,6% dos conjuntos não
   deveria enviesar sistematicamente, a menos que esses 8 sejam atipicamente
   bons/ruins — não testado). Ver `CLAUDE.md`, seção "Lacuna de dados", pra
   a lista exata dos 8 conjuntos.
3. **DscSubestacaoDistribuicao/DscAlimentadorSubestacao não entram no
   cálculo** — DEC/FEC é só por conjunto, não por alimentador/subestação
   (isso é outro projeto, ver `CLAUDE.md` "Granularidade geográfica
   disponível").
4. **Duplicação de sub-eventos por alimentador NÃO é um problema aqui** —
   investigado em 24/08/2026 (ver `CLAUDE.md` item 0): quando uma ocorrência
   atinge mais de um alimentador do mesmo conjunto, isso gera mais de uma
   linha na base — mas são UCs genuinamente diferentes (alimentadores
   diferentes), então cada linha soma corretamente no numerador do DEC/FEC.
   Não precisa (nem deve) deduplicar por conjunto+início+fim antes de rodar
   `05_calcular_dec_fec.R`.

## Decisão 1 — comparação "mesmo período" (fechada em 24/08/2026)

Marco: **"o ideal é um DEC comparado ao mesmo período"** — em vez de
comparar o DEC/FEC parcial de 2026 (só jan-jun) contra o valor **anual
cheio** dos outros anos (o que sub-estimaria 2026 artificialmente, já que
duração/frequência acumulam com o tempo), comparar sempre o mesmo recorte de
meses em todos os anos. Implementado em `scripts/05_calcular_dec_fec.R`
(bloco `dec_fec_mesmo_periodo_sp`), salvo em
`bases/dec_fec_mesmo_periodo_sp.csv`.

**DEC/FEC jan-jun, todo ano (comparação justa):**

| Ano | DEC (jan-jun) | FEC (jan-jun) |
|---|---|---|
| 2018 | 1,97 | 1,32 |
| 2019 | 2,55 | 1,26 |
| 2020 | 2,66 | 1,29 |
| 2021 | 2,53 | 1,29 |
| 2022 | 2,62 | 1,43 |
| 2023 | 2,50 | 1,29 |
| 2024 | 2,92 | 1,40 |
| 2025 | 2,82 | 1,48 |
| **2026** | **2,89** | **1,79** |

**Achado importante que essa correção revelou:** a comparação ingênua (2026
parcial = 2,89h vs. anos anteriores cheios de 4,3-5,8h) fazia 2026 parecer
uma melhora grande — **é um artefato da comparação errada, não uma melhora
real.** Olhando mesmo período: o DEC de jan-jun/2026 é o **segundo maior da
série** (atrás só de 2024), e o **FEC de jan-jun/2026 é o maior de toda a
série** — acima inclusive de 2025, que já era o segundo maior. Ou seja, a
tendência real (mesmo recorte) é de **piora**, não melhora. Esse é
exatamente o tipo de erro editorial que a moldura do projeto quer evitar
(ver `CLAUDE.md`, seção "defasagem de publicação" e avaliação do projeto) —
**nunca comparar DEC/FEC de períodos com cobertura temporal diferente sem
normalizar pelo mesmo recorte de meses.**

## Decisão 2 — resolvida (24/08/2026)

**O "buraco" de 2020-2023 era, em todos os 8 casos, erro de digitação/campo
truncado no shapefile ou conjunto renomeado/absorvido — não ausência real
de dado.** Investigado com fuzzy match (Jaro-Winkler) contra os 143 nomes
do shapefile: 7 dos 8 nomes sem correspondência tinham candidato quase
idêntico (distância <0,30), todos explicáveis por truncamento de campo (ex.
`SAO BERNARDO DO CAMP`, faltando o "O" final — provavelmente limite de
tamanho do campo `NOME` no formato antigo) ou abreviação (`JD. DA GLORIA` →
`JARDIM DA GLORIA`).

**O 8º ("Vargem Grande") pareceu inicialmente insolúvel — mas não era.**
Primeira tentativa: o único candidato por nome no shapefile,
`VARGEM GRANDE PAULIS[TA]` (COD_ID 16592), foi testado geograficamente e
confirmado **município diferente de verdade** (centroide em -47,06/-23,63,
0% de interseção com o polígono do município de SP). Marco então perguntou
diretamente **"você chegou geograficamente [em Vargem Grande]?"** — a
resposta honesta era não: eu tinha só descartado o candidato errado, sem
verificar onde o "Vargem Grande" real (bairro de SP, zona sul) efetivamente
fica. Verificado depois via `UCBT_tab` (tabela de unidades consumidoras da
BDGD, que tem campo de bairro `BRR` e de município `MUN`): existe
**"VARGEM GRANDE" com `MUN=3550308` (São Paulo capital de verdade)**,
classificado sob o conjunto **PARELHEIROS** (COD_ID 12952) — o bairro foi
absorvido por esse conjunto maior em algum momento entre 2019 (último ano
com ID próprio, 12988) e o snapshot do shapefile (dez/2022). Confirmado e
adicionado como alias.

**Achado colateral (via essa investigação):** o ID nativo que a própria
ANEEL usa pra "VARGEM GRANDE" em 2024/2025 (16592) é o **mesmo ID errado**
que aponta pra Vargem Grande Paulista — sugere que o bug de rotulagem não é
só do crosswalk 2020-2023, mas pode estar presente no dado nativo de
2024/2025 também (rows de "Vargem Grande" nesses anos podem estar sendo
excluídos da base pelo filtro geográfico de conjunto, do mesmo jeito que
2020-2023 estavam). **Não corrigido** — afeta um bairro pequeno, não é
prioridade agora, mas fica registrado como possível viés residual em
2018/2019 (ID antigo 12988, não verificável) e 2024/2025.

**Cobertura final de 2020-2023: 100%** (143 de 143 conjuntos), começou em
94,4%. **Impacto no DEC/FEC agregado foi pequeno, como esperado** (é uma
média ponderada — recuperar ~5-6% dos conjuntos não deveria mudar muito o
número, a menos que fossem atipicamente bons/ruins): os valores de
2020-2023 mudaram na casa decimal, não na ordem de grandeza. Números finais
na tabela "Série completa" acima. **Ressalva a manter na página de
metodologia do site:** possível sub-representação pequena de "Vargem
Grande" em 2018/2019/2024/2025 (achado colateral acima) — não em
2020-2023, que já está 100% coberto.

## Índice Apagão-SP — formato de publicação (decisão de 23/08/2026, ainda
não implementada)

Ancorar no **DEC** (duração — o que o consumidor sente), normalizado numa
base fácil de ler (ex. base 100 = média histórica do mesmo mês, pra já
neutralizar sazonalidade sem precisar de média móvel de 12 meses). FEC como
estatística secundária. Evita forçar os dois num índice só com pesos
arbitrários.

## Próximo passo técnico

`scripts/05_calcular_dec_fec.R` já roda ponta a ponta e salva
`bases/dec_fec_mensal_conjunto.rds`/`.csv` e
`bases/dec_fec_mensal_sp.rds`/`.csv`. Falta: implementar o Índice Apagão-SP
(normalização base 100) e decidir as duas pendências acima antes de levar
isso pro site.
