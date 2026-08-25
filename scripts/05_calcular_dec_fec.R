# APAGAO SP - Cálculo do índice DEC/FEC (indicadores oficiais de continuidade,
# PRODIST Módulo 8 da ANEEL) por conjunto elétrico e por mês.
# Marco Antonio Faganello - marcofaga@gmail.com
# Ver CLAUDE.md, seção "Índice Apagão-SP (DEC/FEC)", e bases/DICIONARIO_DADOS.md

# libraries ====================================================================

library(tidyverse)
library(here)

# bd00 - base processada ========================================================

interrsp <- readRDS(here("bases", "interrupcoes-energia-sampa-2018-2026.rds"))

# Checagem defensiva: o campo de expurgo precisa estar presente para todo o
# período antes de filtrar. Se algum ano tiver 100% de NA aqui (como 2026
# tinha antes da correção em harmonizar_2026(), ver scripts/03_montar_base_sampa.R),
# o filtro abaixo descartaria o ano inteiro silenciosamente.
cobertura_expurgo <- interrsp |>
  group_by(NumAno) |>
  summarise(pct_na_expurgo = mean(is.na(IdeMotivoInterrupcao)) * 100, .groups = "drop")
print(cobertura_expurgo)
if (any(cobertura_expurgo$pct_na_expurgo > 5)) {
  stop("IdeMotivoInterrupcao com >5% de NA em pelo menos um ano — checar harmonizar_2026() ",
       "em 03_montar_base_sampa.R antes de prosseguir (base pode precisar ser regerada).")
}

# filtro_dec_fec ================================================================

# Os dois filtros regulatórios que a base principal NÃO aplica (ela serve a
# outros usos descritivos também, não só o DEC/FEC):
#
# 1) Duração mínima de 3 minutos (180s). Achado de 23/08/2026 (ver
#    DICIONARIO_DADOS.md): a base já não tem nenhuma linha abaixo disso —
#    aplicado aqui mesmo assim, de forma explícita, por completude e para não
#    depender desse achado se a base for regerada de outra fonte no futuro.
# 2) Exclusão de "expurgos": qualquer IdeMotivoInterrupcao != 0. O campo é o
#    mesmo que o dicionário oficial da ANEEL chama de IdeMotivoExpurgo — 0
#    significa "não houve expurgo"; 1-8 são os motivos de exclusão regulatória
#    (falha do consumidor, obra exclusiva, emergência, inadimplência,
#    racionamento, dia crítico, alívio de carga ONS, origem externa ao
#    sistema de distribuição).

n_antes <- nrow(interrsp)

interrsp_dec_fec <- interrsp |>
  filter(total >= 180) |>
  filter(IdeMotivoInterrupcao == 0)

n_depois <- nrow(interrsp_dec_fec)
n_expurgado <- n_antes - n_depois

cat(sprintf(
  "Filtro DEC/FEC: %s de %s linhas mantidas (%s expurgadas/curtas, %.1f%%)\n",
  format(n_depois, big.mark = "."), format(n_antes, big.mark = "."),
  format(n_expurgado, big.mark = "."), n_expurgado / n_antes * 100
))

# dec_fec_mensal_conjunto ========================================================

# NumConsumidorConjunto é estável dentro de cada (conjunto, ano, mês) —
# checado em 23/08/2026 (9.342 combinações, todas com 1 único valor) — por
# isso first() abaixo é seguro como denominador do período.

dec_fec_mensal <- interrsp_dec_fec |>
  group_by(IdeConjuntoUnidadeConsumidora, DscConjuntoUnidadeConsumidora, NumAno, mes_inicio) |>
  summarise(
    n_interrupcoes = n(),
    unidades_atingidas = sum(NumUnidadeConsumidora),
    horas_ponderadas = sum(NumUnidadeConsumidora * total_horas),
    consumidores_conjunto = first(NumConsumidorConjunto),
    .groups = "drop"
  ) |>
  mutate(
    DEC = horas_ponderadas / consumidores_conjunto,
    FEC = unidades_atingidas / consumidores_conjunto
  ) |>
  arrange(NumAno, mes_inicio, IdeConjuntoUnidadeConsumidora)

# dec_fec_mensal_sp (agregado da capital) =======================================

# Agregado de toda a capital = tratar o conjunto de conjuntos como um "conjunto
# só": numerador soma direto (é aditivo por natureza), denominador soma o
# consumidores_conjunto de cada conjunto UMA vez por mês (não por evento).

dec_fec_mensal_sp <- dec_fec_mensal |>
  group_by(NumAno, mes_inicio) |>
  summarise(
    n_conjuntos = n_distinct(IdeConjuntoUnidadeConsumidora),
    n_interrupcoes = sum(n_interrupcoes),
    unidades_atingidas = sum(unidades_atingidas),
    horas_ponderadas = sum(horas_ponderadas),
    consumidores_total = sum(consumidores_conjunto),
    .groups = "drop"
  ) |>
  mutate(
    DEC = horas_ponderadas / consumidores_total,
    FEC = unidades_atingidas / consumidores_total
  ) |>
  arrange(NumAno, mes_inicio)

# dec_fec_anual_sp (sanity check contra a cartilha ARSESP) ======================

dec_fec_anual_sp <- interrsp_dec_fec |>
  group_by(IdeConjuntoUnidadeConsumidora, NumAno) |>
  summarise(
    unidades_atingidas = sum(NumUnidadeConsumidora),
    horas_ponderadas = sum(NumUnidadeConsumidora * total_horas),
    consumidores_conjunto = first(NumConsumidorConjunto[mes_inicio == max(mes_inicio)]),
    .groups = "drop"
  ) |>
  group_by(NumAno) |>
  summarise(
    consumidores_total = sum(consumidores_conjunto),
    horas_ponderadas = sum(horas_ponderadas),
    unidades_atingidas = sum(unidades_atingidas),
    .groups = "drop"
  ) |>
  mutate(
    DEC = horas_ponderadas / consumidores_total,
    FEC = unidades_atingidas / consumidores_total
  )

cat("\n=== DEC/FEC anual, SP capital (sanity check vs. cartilha ARSESP Enel SP: ",
    "DEC 2022=6,36h / FEC 2022=3,40) ===\n")
print(dec_fec_anual_sp |> select(NumAno, DEC, FEC))
cat(
  "\nNota: a cartilha ARSESP cobre toda a área de concessão da Enel SP (região\n",
  "metropolitana), não só a capital — divergência esperada, não é validação\n",
  "exata, só checagem de ordem de grandeza.\n", sep = ""
)

# dec_fec_mesmo_periodo_sp (comparacao justa pro ano parcial) ==================

# Decisao de 24/08/2026 (Marco): "o ideal e' um DEC comparado ao mesmo
# periodo" -- em vez de comparar o DEC anual parcial de 2026 (so jan-jun)
# contra o DEC anual CHEIO dos anos anteriores (o que sub-estimaria 2026
# artificialmente), comparar sempre o mesmo recorte de meses (jan-jun) em
# todos os anos. Resolve a pendencia registrada em bases/METODOLOGIA_DEC_FEC.md.

mes_max_2026 <- max(interrsp_dec_fec$mes_inicio[interrsp_dec_fec$NumAno == 2026])
cat("\nUltimo mes disponivel em 2026:", mes_max_2026, "-- comparando jan-", mes_max_2026, " de cada ano\n", sep = "")

dec_fec_mesmo_periodo_sp <- interrsp_dec_fec |>
  filter(mes_inicio <= mes_max_2026) |>
  group_by(IdeConjuntoUnidadeConsumidora, NumAno) |>
  summarise(
    unidades_atingidas = sum(NumUnidadeConsumidora),
    horas_ponderadas = sum(NumUnidadeConsumidora * total_horas),
    consumidores_conjunto = first(NumConsumidorConjunto[mes_inicio == max(mes_inicio)]),
    .groups = "drop"
  ) |>
  group_by(NumAno) |>
  summarise(
    consumidores_total = sum(consumidores_conjunto),
    horas_ponderadas = sum(horas_ponderadas),
    unidades_atingidas = sum(unidades_atingidas),
    .groups = "drop"
  ) |>
  mutate(
    DEC = horas_ponderadas / consumidores_total,
    FEC = unidades_atingidas / consumidores_total
  )

cat("\n=== DEC/FEC jan-", mes_max_2026, ", SP capital, mesmo periodo todo ano ===\n", sep = "")
print(dec_fec_mesmo_periodo_sp |> select(NumAno, DEC, FEC))

write_csv(dec_fec_mesmo_periodo_sp, here("bases", "dec_fec_mesmo_periodo_sp.csv"))

# save ===========================================================================

saveRDS(dec_fec_mensal, here("bases", "dec_fec_mensal_conjunto.rds"))
write_csv(dec_fec_mensal, here("bases", "dec_fec_mensal_conjunto.csv"))

saveRDS(dec_fec_mensal_sp, here("bases", "dec_fec_mensal_sp.rds"))
write_csv(dec_fec_mensal_sp, here("bases", "dec_fec_mensal_sp.csv"))

beepr::beep()
