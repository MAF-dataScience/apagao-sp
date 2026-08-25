# Dicionário de Dados — `interrupcoes-energia-sampa-2018-2026.rds`

Registro descritivo da base processada do projeto Apagão-SP. Gerado por inspeção direta do arquivo em 23/08/2026 (ver `scripts/03_montar_base_sampa.R` para o pipeline que produz esta base).

## O que é a base

**1.764.910 linhas × 29 colunas** (24/08/2026 — regenerada após dedupe de duplicata exata e depois após correção completa do crosswalk de conjunto 2020-2023, ver "Notas de qualidade" abaixo; passou por 1.738.906 → 1.738.895 → 1.759.211 → 1.764.910). Dado tabular (tibble), sem geometria anexada.

## Glossário

Hierarquia de termos elétricos usada nesta base, do mais granular ao mais amplo:

- **Unidade consumidora (UC):** uma ligação de energia — um medidor. Na prática, uma casa, apartamento ou loja. É o nível mais fino que existe, mas **a base não identifica UC individual** — só conta quantas foram atingidas por evento (`NumUnidadeConsumidora`).
- **Alimentador:** o circuito que sai de uma subestação e leva energia até os consumidores de uma área. É o nível mais fino que a base *identifica* (2018-2025: `DscAlimentadorSubestacao`, nome; 2026: código).
- **Subestação:** a instalação que recebe energia em alta tensão e distribui pra uma região (o que alimenta os alimentadores).
- **Conjunto elétrico** (ou "conjunto de unidades consumidoras"): agrupamento administrativo/regulatório de dezenas de milhares de unidades consumidoras, definido pela distribuidora — na prática, corresponde a um bairro ou região da cidade. É a unidade que a ANEEL usa como referência pra publicar indicadores de continuidade (DEC/FEC) por região, e a que dá nome aos "bairros" do relatório do projeto (`DscConjuntoUnidadeConsumidora`/`IdeConjuntoUnidadeConsumidora`). SP capital tem 99 conjuntos únicos nesta base, cada um com entre ~8.600 e ~160.000 unidades consumidoras (`NumConsumidorConjunto`).

Relação entre eles: alimentador e subestação descrevem **por onde a energia passa fisicamente**; conjunto é um recorte **administrativo/comercial** de consumidores, não necessariamente alinhado 1:1 com um alimentador — um conjunto (bairro) costuma ser atendido por vários alimentadores diferentes. É por isso que um mesmo evento de interrupção pode gerar mais de uma linha no mesmo conjunto: um alimentador saiu do ar, mas outro alimentador do mesmo bairro não (ver "Unidade de observação" abaixo).

## Unidade de observação

**Cada linha é um evento de interrupção não programada de energia elétrica, reportado pela distribuidora para um conjunto elétrico** (agrupamento de unidades consumidoras — ver `CLAUDE.md`, glossário implícito na seção de fonte de dados) na cidade de São Paulo.

**Não é uma unidade consumidora (domicílio/ligação) por linha.** `NumUnidadeConsumidora` é uma **contagem agregada** — quantas unidades consumidoras do conjunto foram atingidas *naquele evento específico* —, não um identificador individual. Duas famílias de consumidor no mesmo conjunto, atingidas pelo mesmo evento, geram **uma linha só** com `NumUnidadeConsumidora = 2`, não duas linhas.

**A granularidade real é conjunto × subestação × alimentador, não só conjunto** (achado de 24/08/2026, investigação de duplicação — ver `CLAUDE.md` "Próximos passos" e `LOG.md`). Uma mesma ocorrência física de interrupção pode gerar 2+ linhas legítimas quando atinge mais de um alimentador dentro do mesmo conjunto — mesmo início/fim/causa/unidades atingidas, `DscAlimentadorSubestacao` diferente. Isso **não é duplicata**: é o grão real do registro que a distribuidora envia ao DutoNet da ANEEL. Confirmado com evidência direta no schema 2026 (que trafega `CodAlimentador`/`CodSubestacao` como código, harmonizado pra este campo em 24/08/2026 — antes vinha `NA`, o que mascarava esses sub-eventos como se fossem duplicata de conjunto). Portanto: **não agrupar/deduplicar por (conjunto, início, fim, unidades atingidas) sem incluir subestação/alimentador na chave** — fazer isso descartaria eventos reais, não duplicatas.

**Distribuidora:** uma só — `ELETROPAULO METROPOLITANA ELETRICIDADE DE SAO PAULO S.A.` (Enel SP), monopólio na capital.

## Cobertura

- **Temporal:** 2018-01-01 a 2026-06-30/07-01 (2026 parcial — só jan-jun, ver `CLAUDE.md` seção "Defasagem de publicação"). 2017 fora do escopo (Eletropaulo ausente da fonte nesse ano).
- **Geográfica:** conjuntos elétricos que intersectam o município de São Paulo em >50% de área (99 conjuntos únicos na base).
- **Por ano:** 2018 (144.922) · 2019 (137.313) · 2020 (146.905) · 2021 (153.169) · 2022 (195.529) · 2023 (233.219) · 2024 (278.413) · 2025 (308.559) · 2026 (166.881, parcial). 2020-2023 subiram após a correção completa do crosswalk de conjunto (94,4%→100% de cobertura, ver `CLAUDE.md` "Lacuna de dados" e `bases/METODOLOGIA_DEC_FEC.md`).

## Filtros já aplicados (não é o dado bruto da ANEEL)

- `causa_01 == "INTERNA"` (exclui causas externas ao sistema de distribuição)
- `causa_02 == "NAO PROGRAMADA"` (exclui interrupções programadas — mas ver ressalva de `DscTipoInterrupcao` abaixo)
- `causa_03 != "NAO CLASSIFICADA"`
- `causa_04` não é "empresas de serviços públicos ou suas contratadas" nem "não identificada"
- Conjunto elétrico precisa estar em SP capital (critério de área de interseção >50%, ver `CLAUDE.md`)

**Não aplicado ainda:** filtro de duração mínima (3min) e exclusão de "expurgos" regulatórios (`IdeMotivoInterrupcao`/`IdeMotivoExpurgo`) — necessários para o índice DEC/FEC oficial, mas não para o uso descritivo geral da base. Ver `CLAUDE.md`, seção "Índice Apagão-SP (DEC/FEC)".

## Dicionário de colunas

| Coluna | Tipo | Descrição | Notas |
|---|---|---|---|
| `DatGeracaoConjuntoDados` | Date | Data de geração/processamento do extrato anual da ANEEL | Uma data por arquivo-ano, não por registro — não usar para medir defasagem por linha (ver `CLAUDE.md`) |
| `IdeConjuntoUnidadeConsumidora` | numeric | Código do conjunto elétrico (agrupamento de unidades consumidoras) | 99 valores únicos na base; para 2020-2023 recuperado via crosswalk nome→id (`bases/crosswalk_conjuntos_sp.rds`) |
| `DscConjuntoUnidadeConsumidora` | character | Nome do conjunto elétrico (ex: bairro/região) | |
| `DscAlimentadorSubestacao` | character | Alimentador/circuito de onde partiu a interrupção | Em 2026 vem de `CodAlimentador` (código, não descrição textual) — mapeado em 24/08/2026, ver "Notas de qualidade" |
| `DscSubestacaoDistribuicao` | character | Subestação de distribuição | **100% ausente em 2026** — não é bug de harmonização, `CodSubestacao` já vem `NA` no raw da Eletropaulo (e de várias outras distribuidoras grandes), ver "Notas de qualidade" |
| `NumOrdemInterrupcao` | character | Identificador do registro de interrupção (ex: `"40932400-1"`) | Não é (nem nunca foi) chave única — 100.012 valores repetidos na base; ver "Notas de qualidade" |
| `DscTipoInterrupcao` | character | "Não Programada" / "Programada" (campo oficial da ANEEL) | 211 linhas marcadas "Programada" sobreviveram ao filtro de `causa_02` (que usa texto de causa, não este campo) — ver "Notas de qualidade" |
| `IdeMotivoInterrupcao` | numeric | Código de motivo de expurgo regulatório (mesmo campo que a ANEEL chama `IdeMotivoExpurgo`: 0=não houve expurgo, 1=falha na instalação do consumidor, 2=obra exclusiva do consumidor, 3=emergência, 4=inadimplência/deficiência técnica, 5=racionamento, 6=dia crítico, 7=alívio de carga ONS, 8=origem externa) | Mapeado em 2026 desde 24/08/2026 (era 100% ausente). Valores em 2018-2025: 0 (1.400.449), 3 (74.384), 6 (97.190), 8 (2); em 2026: 0, 3, 6 |
| `DatInicioInterrupcao` | POSIXct | Início da interrupção | |
| `DatFimInterrupcao` | POSIXct | Fim (restabelecimento) da interrupção | |
| `DscFatoGeradorInterrupcao` | character | Texto de causa, separado por `;` (2018-2025) ou recombinado de 4 campos com `" - "` (2026, ver `harmonizar_2026()`) | Fonte de `causa_01`–`causa_04` |
| `NumNivelTensao` | numeric | Nível de tensão (volts) onde o fato gerador foi verificado | Predomina baixa tensão 240V (1.382.254 linhas) e média tensão 13.800V (354.512 linhas) |
| `NumUnidadeConsumidora` | numeric | Nº de unidades consumidoras atingidas **naquele evento** | Min 1, mediana 1, média 96,3, máx 20.688 — distribuição de cauda longa (a maioria dos eventos atinge pouquíssimas unidades) |
| `NumConsumidorConjunto` | numeric | Total de unidades consumidoras do conjunto (denominador) | Varia de 8.591 a 159.709 por conjunto |
| `NumAno` | numeric | Ano de início da interrupção | |
| `NomAgenteRegulado` | character | Nome da distribuidora | Valor único: Eletropaulo/Enel SP |
| `SigAgente` | character | Sigla da distribuidora | |
| `NumCPFCNPJ` | character | CNPJ da distribuidora | |
| `inicio_ts` / `fim_ts` | numeric | Timestamps Unix derivados de início/fim | Colunas auxiliares de cálculo |
| `total` | numeric | Duração em segundos (`fim_ts - inicio_ts`) | |
| `total_horas` | numeric | Duração em horas | Min 0,050h (exatamente 3min — nenhuma linha abaixo disso, ver "Notas de qualidade"), mediana 4,24h, máx 906,6h |
| `mes_inicio` / `mes_fim` | numeric | Mês (1-12) de início/fim | |
| `causa_01` | character | Nível 1 da taxonomia de causa (após split) | Sempre "INTERNA" (filtro já aplicado) |
| `causa_02` | character | Nível 2 | Sempre "NAO PROGRAMADA" (filtro já aplicado) |
| `causa_03` | character | Nível 3 — nível mais usado na prática | 4 categorias: PROPRIAS DO SISTEMA (1.023.474), MEIO AMBIENTE (327.685), TERCEIROS (290.627), FALHA OPERACIONAL (97.120) |
| `causa_04` | character | Nível 4 (mais granular) | |
| `prop_atingidas` | numeric | `NumUnidadeConsumidora / NumConsumidorConjunto * 100` | Min 0,0006%, mediana 0,002%, máx 46,99% — nunca passa de 100% |

## Notas de qualidade de dado

- **`IdeMotivoInterrupcao` — resolvido em 24/08/2026.** Estava 100% ausente em 2026 (bloqueava o filtro de expurgo do DEC/FEC pra esse ano); `harmonizar_2026()` agora mapeia `DscMotivoExpurgo` → código. Base regenerada: 0 `NA` em 2026 (valores 0, 3 e 6 presentes — mesma faixa dos anos anteriores).
- **`DscAlimentadorSubestacao` — resolvido em 24/08/2026** (100% ausente antes, harmonização não mapeava). Agora vem de `CodAlimentador` (código, não descrição textual como em 2018-2025 — ainda assim serve pra diferenciar sub-eventos, ver "Unidade de observação" acima).
- **`DscSubestacaoDistribuicao` — mapeado mas continua 100% ausente em 2026** (investigado em 24/08/2026): não é bug de harmonização — `CodSubestacao` já vem `NA` no raw nacional pra Eletropaulo (confirmado: 0/251.199 linhas preenchidas). Não é falha exclusiva da Eletropaulo — RGE Sul, CPFL, Coelba, Equatorial Maranhão e outras grandes distribuidoras também têm 100% de ausência nesse campo; só CEMIG, COPEL e Energisa Goiás preenchem. Parece refletir uma diferença de sistema de origem entre distribuidoras, não erro de carga da ANEEL.
- **Duração mínima já é exatamente 3min (0,050h) em toda a base, sem nenhuma linha abaixo disso** — sugere que a ANEEL já aplica esse corte na fonte, ou que o filtro de duração mínima do DEC/FEC pode já estar satisfeito por construção. **Não confirmado formalmente** — checar de novo ao implementar o filtro de duração no cálculo de DEC/FEC, em vez de assumir.
- **211 linhas com `DscTipoInterrupcao == "Programada"`** sobrevivem ao filtro de `causa_02 == "NAO PROGRAMADA"` — os dois campos (tipo oficial vs. taxonomia de causa derivada do texto) não concordam em todos os casos. Volume pequeno (0,01% da base), não investigado a fundo.
- **Duplicata exata — resolvido em 24/08/2026.** Linhas 100% duplicadas (concentradas em 2020) foram confirmadas como duplicata real já no raw nacional da ANEEL (não efeito do crosswalk) — 14 linhas nacionais, todas dentro de SP capital depois da correção de cobertura do crosswalk (11 antes da correção, ver `CLAUDE.md` "Lacuna de dados"). `distinct()` adicionado como rede de segurança em `03_montar_base_sampa.R`, logo após o `bind_rows()`. Base regenerada: 0 duplicata exata remanescente em todas as versões.
- **"413 linhas compartilhando conjunto+início+fim+unidades" — era falso positivo, investigado e majoritariamente resolvido em 24/08/2026.** A unidade real de observação é conjunto × subestação × alimentador (ver "Unidade de observação" acima) — a harmonização de 2026 descartava alimentador/subestação, fazendo sub-eventos legítimos parecerem duplicata de conjunto. Com `DscAlimentadorSubestacao` mapeado: caiu pra 119 grupos / 241 linhas (de 166.881, 0,14%) compartilhando conjunto+início+fim+unidades; considerando também subestação (100% `NA` em 2026, não ajuda a diferenciar — ver nota acima) o residual fica em 97 grupos / 197 linhas. Esse residual é do mesmo tipo (pequeno, ambíguo) já observado em 2018-2025 depois de incluir subestação/alimentador na checagem — normalmente `NumOrdemInterrupcao` ou a causa diferem, sugerindo registros administrativamente distintos, não duplicata. Volume desprezível, não deduplicado.
- **`NumOrdemInterrupcao`/`CodInterrupcao` não são (e nunca foram) chave única** — não é falha de dado. O dicionário oficial da ANEEL define `NumOrdemInterrupcao` como referência a "Ofício ou normativo determinando interrupções de energia", não um identificador de registro. No schema 2026, `CodInterrupcao` chega a ter ~106 mil valores repetidos nacionalmente, mas isso está concentrado em ~10 distribuidoras regionais pequenas com esquema de ID fraco/colisível (ex. Companhia Jaguari, 88% de repetição — usa códigos tipo data que colidem entre agentes); **pra Eletropaulo/SP especificamente, `CodInterrupcao` é 100% único** (251.199 linhas, 251.199 valores únicos, nacional). Não usar nenhum dos dois como identificador de linha.

## Proveniência

Ver `CLAUDE.md` (seção "Fonte dos dados" e "Lacuna de dados") e `scripts/03_montar_base_sampa.R` para o pipeline completo de construção desta base a partir dos microdados brutos da ANEEL.
