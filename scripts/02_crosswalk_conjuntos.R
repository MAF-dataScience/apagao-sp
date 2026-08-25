# Crosswalk nome -> COD_ID de conjunto elétrico
# Gerado em 23/08/2026 (ver LOG.md e CLAUDE.md, seção "Lacuna de dados")
#
# Fonte única de verdade: o shapefile CONJ (raw/interrup_energia/ENEL_SP_390...gdb.zip),
# não os anos de referência com ID nativo (2017/2018/2019/2024/2025) — testado e
# descartado esse caminho porque um conjunto só aparece na lista de nomes de um ano
# se teve pelo menos 1 interrupção registrada naquele ano. O shapefile cobre os
# 143 conjuntos de uma vez, independente de histórico de interrupção.
#
# Resolve a lacuna de IdeConjuntoUnidadeConsumidora ausente em 2020-2023.
# Rodar em R 4.5.1 (versão mais recente instalada nesta máquina — sf/geobr/here
# instalados nela em 23/08/2026 pra unificar, ver CLAUDE.md "Ambiente técnico").

suppressPackageStartupMessages({
  library(dplyr)
  library(stringi)
  library(sf)
  library(readr)
  library(here)
  library(arrow)
})

raw <- here("raw", "interrup_energia")
parquet_dir <- file.path(raw, "parquet")

normalizar <- function(x) stri_trans_general(toupper(trimws(x)), "Latin-ASCII")

# Leitura via parquet (24/08/2026, ver CLAUDE.md "Fonte dos dados") em vez de
# readRDS() do RDS nacional — filtro por agente já no open_dataset() (pushdown
# via arrow, antes de materializar em R).
ler_ano_eletropaulo <- function(ano) {
  open_dataset(file.path(parquet_dir, paste0("interrupcoes-energia-eletrica-", ano, ".parquet"))) |>
    filter(grepl("ELETROPAULO", toupper(NomAgenteRegulado))) |>
    collect()
}

# 1. Crosswalk a partir do shapefile ===========================================

conjuntos <- read_sf(file.path(raw, "ENEL_SP_390_2022-12-31_V11_20231001-2204.gdb.zip"), layer = "CONJ")

xwalk <- conjuntos %>%
  sf::st_drop_geometry() %>%
  transmute(nome_norm = normalizar(NOME), cod_id = COD_ID) %>%
  distinct()

# Alias manual pros nomes que davam "sem match" antes de 24/08/2026 — investigado
# com fuzzy match (Jaro-Winkler, ver LOG.md) + confirmado um a um com Marco.
# 7 de 8 eram erro de digitação/truncamento no proprio campo NOME do shapefile
# (nao ausencia real de conjunto) — ex. "SAO BERNARDO DO CAMP" (faltando o
# "O" final, provavelmente limite de tamanho de campo do formato antigo).
#
# O 8o ("VARGEM GRANDE") pareceu inicialmente um buraco real: o unico
# candidato por nome no shapefile e' "VARGEM GRANDE PAULIS[TA]" (COD_ID
# 16592), que E' municipio diferente de verdade (MUN=3556453, confirmado
# geograficamente — 0% de intersecao com o municipio de SP). Mas Marco
# perguntou "voce chegou geograficamente [em Vargem Grande]?" — nao tinha
# chegado, só tinha descartado o candidato errado. Verificado depois via
# UCBT_tab (BDGD): "VARGEM GRANDE" com MUN=3550308 (SP capital de verdade)
# existe e esta` classificado sob o conjunto PARELHEIROS (COD_ID 12952) —
# provavelmente foi absorvido pelo Parelheiros em algum momento entre 2019
# (ultimo ano com ID proprio, 12988) e o snapshot do shapefile (dez/2022).
alias_conjuntos <- tibble(
  nome_norm = c(
    "TABOAO DA SERRA", "SAO BERNARDO DO CAMPO", "JUSCELINO KUBITSCHEK",
    "JD. DA GLORIA", "ALEX. DE GUSMAO", "MIGUEL REALE_RETICULADO",
    "BANDEIRANTES_RETICULADO", "VARGEM GRANDE"
  ),
  cod_id = c(
    xwalk$cod_id[xwalk$nome_norm == "TABAO DA SERRA"],
    xwalk$cod_id[xwalk$nome_norm == "SAO BERNARDO DO CAMP"],
    xwalk$cod_id[xwalk$nome_norm == "JUCELINO KUBITSCHEK"],
    xwalk$cod_id[xwalk$nome_norm == "JARDIM DA GLORIA"],
    xwalk$cod_id[xwalk$nome_norm == "ALEXANDRE GUSMAO"],
    xwalk$cod_id[xwalk$nome_norm == "MIGUEL REALE RETICUL"],
    xwalk$cod_id[xwalk$nome_norm == "BANDEIRANTES RETICUL"],
    xwalk$cod_id[xwalk$nome_norm == "PARELHEIROS"]
  )
)
stopifnot(!anyNA(alias_conjuntos$cod_id))
xwalk <- bind_rows(xwalk, alias_conjuntos)

stopifnot(!any(duplicated(xwalk$nome_norm)))
cat("Crosswalk construído a partir do shapefile CONJ:", nrow(xwalk), "conjuntos\n\n")

# 2. Validação contra anos que já têm ID nativo ================================

anos_ref <- c(2017, 2018, 2019, 2024, 2025)

for (ano in anos_ref) {
  d_elet <- ler_ano_eletropaulo(ano)
  d_elet$NomAgenteRegulado <- trimws(d_elet$NomAgenteRegulado)

  pares <- d_elet %>%
    mutate(nome_norm = normalizar(DscConjuntoUnidadeConsumidora)) %>%
    distinct(nome_norm, IdeConjuntoUnidadeConsumidora)

  checagem <- pares %>%
    left_join(xwalk, by = "nome_norm") %>%
    mutate(bate = IdeConjuntoUnidadeConsumidora == cod_id)

  n_sem_match <- sum(is.na(checagem$cod_id))
  n_diverge <- sum(!checagem$bate, na.rm = TRUE)

  cat(sprintf("Validação %d: %d conjuntos, %d sem match no shapefile, %d com ID divergente\n",
              ano, nrow(checagem), n_sem_match, n_diverge))
  if (n_sem_match > 0) cat("  Sem match:", paste(checagem$nome_norm[is.na(checagem$cod_id)], collapse = ", "), "\n")
  if (n_diverge > 0) print(checagem %>% filter(!bate))

  rm(d_elet)
  gc()
}

cat("\n")

# 3. Aplicar o crosswalk em 2020-2023 (lacuna) ==================================

for (ano in 2020:2023) {
  d_elet <- ler_ano_eletropaulo(ano)
  d_elet$NomAgenteRegulado <- trimws(d_elet$NomAgenteRegulado)

  nomes_unicos <- d_elet %>%
    mutate(nome_norm = normalizar(DscConjuntoUnidadeConsumidora)) %>%
    distinct(nome_norm) %>%
    left_join(xwalk, by = "nome_norm")

  n_sem_match <- sum(is.na(nomes_unicos$cod_id))
  cat(sprintf("Aplicação %d: %d conjuntos únicos, %d sem match (%.1f%%)\n",
              ano, nrow(nomes_unicos), n_sem_match, 100 * n_sem_match / nrow(nomes_unicos)))
  if (n_sem_match > 0) cat("  Sem match:", paste(nomes_unicos$nome_norm[is.na(nomes_unicos$cod_id)], collapse = ", "), "\n")

  rm(d_elet)
  gc()
}

# 4. Salvar o crosswalk como referência para o pipeline principal ==============

saveRDS(xwalk, here("bases", "crosswalk_conjuntos_sp.rds"))
write_csv(xwalk, here("bases", "crosswalk_conjuntos_sp.csv"))
cat("\nCrosswalk salvo em bases/crosswalk_conjuntos_sp.rds (+ .csv)\n")
