# Compara os extratos baixados da ANEEL em 14/11/2026 (publicação de 12/11/2026)
# com os parquets em uso. Converte cada CSV novo para parquet em staging e
# resume, nacional e Eletropaulo: linhas, colunas, datas mín/máx.
# Uso: Rscript auditoria/20261114_comparar_extratos.R

library(readr); library(arrow); library(dplyr); library(here)

raw <- here("raw", "interrup_energia")
dl <- file.path(raw, "download_20261114")
stg <- file.path(dl, "parquet_staging"); dir.create(stg, showWarnings = FALSE)

resumo <- function(p, ano) {
  ds <- open_dataset(p)
  nm <- names(ds)
  ag <- intersect(c("NomAgenteRegulado", "NomAgente", "SigAgente"), nm)
  ini <- intersect(c("DatInicioInterrupcao"), nm)
  n <- ds |> count() |> collect() |> pull(n)
  agcol <- ag[1]
  el <- ds |> filter(grepl("ELETROPAULO|ENEL SP|Enel SP", .data[[agcol]])) |>
    select(all_of(ini)) |> collect()
  tibble(ano = ano, ncol = length(nm), linhas = n, col_agente = agcol,
         linhas_sp = nrow(el),
         ini_min = min(el[[1]], na.rm = TRUE), ini_max = max(el[[1]], na.rm = TRUE))
}

out <- list()
for (a in 2023:2026) {
  csv <- paste0("interrupcoes-energia-eletrica-", a, ".csv")
  pq_new <- file.path(stg, paste0("interrupcoes-energia-eletrica-", a, ".parquet"))
  if (!file.exists(pq_new)) {
    unzip(file.path(dl, paste0("interrupcoes-energia-eletrica-", a, ".zip")), files = csv, exdir = tempdir(), overwrite = TRUE)
    d <- read_csv2(file.path(tempdir(), csv), locale = locale(encoding = "UTF-8"), show_col_types = FALSE)
    write_parquet(d, pq_new); file.remove(file.path(tempdir(), csv)); rm(d); gc()
  }
  pq_old <- file.path(raw, "parquet", paste0("interrupcoes-energia-eletrica-", a, ".parquet"))
  out[[length(out) + 1]] <- mutate(resumo(pq_old, a), versao = "atual")
  out[[length(out) + 1]] <- mutate(resumo(pq_new, a), versao = "nova_12nov")
  cat("ano", a, "ok\n")
  old_n <- names(open_dataset(pq_old)); new_n <- names(open_dataset(pq_new))
  if (!identical(old_n, new_n)) cat("  colunas diferentes. so na nova:", setdiff(new_n, old_n), "| so na atual:", setdiff(old_n, new_n), "\n")
}
print(as.data.frame(bind_rows(out)))
