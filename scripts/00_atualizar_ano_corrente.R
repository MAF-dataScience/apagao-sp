# Atualização mensal de rotina: reconverte o extrato do ano corrente (baixado
# de novo da ANEEL) para parquet, sobrescrevendo só esse ano — os demais anos
# da série são históricos e não mudam mês a mês, não precisam ser reprocessados.
# Rodar depois de baixar o zip atualizado em
# raw/interrup_energia/interrupcoes-energia-eletrica-<ano_corrente>.zip.
#
# Link direto do zip de 2026 (ANEEL, dados abertos; o resource id muda a cada ano,
# ver lista em https://dadosabertos.aneel.gov.br/api/3/action/package_show?id=interrupcoes-de-energia-eletrica-nas-redes-de-distribuicao):
# https://dadosabertos.aneel.gov.br/dataset/ccb25653-f07b-4f28-84c2-62a89d1f5a56/resource/33a21bd6-4893-42fc-bc05-888154f7511e/download/interrupcoes-energia-eletrica-2026.zip
# Antes de baixar, conferir se há versão nova: HEAD no link e comparar Content-Length/
# Last-Modified com o zip local (em 01/10/2026: 202.900.063 bytes, Last-Modified 04/09/2026,
# idêntico ao baixado em 10/09 — ou seja, ANEEL ainda não tinha publicado ago/2026). Rechecado em 21/10/2026: ainda
# o mesmo arquivo (jan-jul); no portal só os dicionários de dados mudaram, em 19/10.
# A ANEEL também publica .parquet por ano no mesmo dataset (resource próprio), o que
# permitiria pular a conversão CSV->parquet. Ainda não testado se o schema é idêntico.
# Baixar via PowerShell com TLS1.2 forçado (Invoke-WebRequest).
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
