# Conversão dos dados brutos ANEEL (interrupções nacionais, por ano) para
# parquet particionado por ano — substitui os RDS como formato de leitura do
# raw/ (RDS mantido por enquanto, não apagado nesta sessão).
#
# Motivação (23-24/08/2026, ver LOG.md): o pipeline principal (03_montar_base_sampa.R)
# le o RDS nacional inteiro (5-10M linhas/ano) so pra filtrar ~250-470k linhas
# da Eletropaulo — parquet com leitura via arrow (predicate/column pushdown)
# evita carregar o Brasil inteiro na RAM pra descartar 95% depois.
#
# Fonte por ano:
# - 2023-2026: direto do CSV bruto (raw/interrup_energia/raw/*.csv), igual aos
#   scripts 01_converter_2023_2024.R / 01_converter_2025_2026.R (mesmo locale
#   UTF-8 — ver notas desses scripts). Validado comparando nrow() com o RDS já
#   existente pra esses anos (convertido do mesmo CSV, serve de checagem de
#   integridade).
# - 2017-2022: CSV bruto não existe mais localmente (só o RDS já convertido
#   permanece em raw/) — convertido a partir do RDS, que já é a representação
#   fiel do CSV original (nenhuma perda: é o mesmo objeto R, só serializado em
#   outro formato).
#
# Layout: raw/interrup_energia/parquet/interrupcoes-energia-eletrica-AAAA.parquet
# — arquivo plano por ano, mesmo padrão de nome do RDS. Testado particionamento
# Hive-style (ano=AAAA/part-0.parquet) primeiro, mas descartado (24/08/2026,
# pedido de Marco): só compensa quando uma query varre vários anos de uma vez;
# aqui o pipeline sempre processa ano a ano (schema muda de ano pra ano,
# harmonização é manual mesmo) — a pasta extra era ritual sem benefício prático.

library(readr)
library(arrow)
library(here)

raw <- here("raw", "interrup_energia")
parquet_dir <- file.path(raw, "parquet")
dir.create(parquet_dir, showWarnings = FALSE)

escrever_parquet <- function(df, ano) {
  dest_file <- file.path(parquet_dir, paste0("interrupcoes-energia-eletrica-", ano, ".parquet"))
  write_parquet(df, dest_file)
  cat(ano, "- parquet escrito:", nrow(df), "linhas ->", dest_file, "\n")
}

# 2023-2026 — direto do CSV, com checagem de integridade contra o RDS existente
anos_csv <- 2023:2026
for (ano in anos_csv) {
  cat("\n===", ano, "(via CSV) ===\n")
  csv_path <- file.path(raw, "raw", paste0("interrupcoes-energia-eletrica-", ano, ".csv"))
  rds_path <- file.path(raw, paste0("interrupcoes-energia-eletrica-", ano, ".rds"))

  d <- read_csv2(csv_path, locale = locale(encoding = "UTF-8"))
  cat("CSV lido:", nrow(d), "linhas,", ncol(d), "colunas\n")

  if (file.exists(rds_path)) {
    d_rds <- readRDS(rds_path)
    if (nrow(d) == nrow(d_rds) && ncol(d) == ncol(d_rds)) {
      cat("Checagem de integridade OK (nrow/ncol batem com o RDS existente)\n")
    } else {
      cat("*** ATENCAO: nrow/ncol NAO batem com o RDS existente — CSV:", nrow(d), ncol(d), " RDS:", nrow(d_rds), ncol(d_rds), "***\n")
    }
    rm(d_rds); gc()
  }

  escrever_parquet(d, ano)
  rm(d); gc()
}

# 2017-2022 — a partir do RDS ja existente (CSV bruto nao existe mais localmente)
anos_rds <- 2017:2022
for (ano in anos_rds) {
  cat("\n===", ano, "(via RDS, CSV bruto indisponivel localmente) ===\n")
  rds_path <- file.path(raw, paste0("interrupcoes-energia-eletrica-", ano, ".rds"))
  d <- readRDS(rds_path)
  cat("RDS lido:", nrow(d), "linhas,", ncol(d), "colunas\n")
  escrever_parquet(d, ano)
  rm(d); gc()
}

cat("\n=== Conversao concluida. Validando leitura arquivo a arquivo ===\n")
for (ano in c(anos_csv, anos_rds)) {
  f <- file.path(parquet_dir, paste0("interrupcoes-energia-eletrica-", ano, ".parquet"))
  n <- nrow(read_parquet(f, col_select = 1))
  cat(ano, "-", n, "linhas (lido de volta do parquet)\n")
}

beepr::beep()
