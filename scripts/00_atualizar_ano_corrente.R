# Atualização mensal de rotina: reconverte o extrato do ano corrente (baixado
# de novo da ANEEL) para parquet, sobrescrevendo só esse ano — os demais anos
# da série são históricos e não mudam mês a mês, não precisam ser reprocessados.
# Rodar depois de baixar o zip atualizado em
# raw/interrup_energia/interrupcoes-energia-eletrica-<ano_corrente>.zip.
#
# Complementa (não substitui) o 01_converter_parquet.R, que fez a migração
# histórica única de todos os anos em 24/08/2026.

library(readr)
library(arrow)
library(here)

ano_corrente <- 2026

raw <- here("raw", "interrup_energia")
zip_path <- file.path(raw, paste0("interrupcoes-energia-eletrica-", ano_corrente, ".zip"))
parquet_path <- file.path(raw, "parquet", paste0("interrupcoes-energia-eletrica-", ano_corrente, ".parquet"))

csv_name <- paste0("interrupcoes-energia-eletrica-", ano_corrente, ".csv")
tmp_dir <- tempdir()
unzip(zip_path, files = csv_name, exdir = tmp_dir, overwrite = TRUE)
csv_path <- file.path(tmp_dir, csv_name)

d <- read_csv2(csv_path, locale = locale(encoding = "UTF-8"))
cat("CSV lido:", nrow(d), "linhas,", ncol(d), "colunas\n")

write_parquet(d, parquet_path)
cat("Parquet atualizado:", nrow(d), "linhas ->", parquet_path, "\n")

file.remove(csv_path)
beepr::beep()
