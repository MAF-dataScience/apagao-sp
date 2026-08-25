# Conversão dos CSVs brutos ANEEL 2025/2026 para RDS
# Gerado em 23/08/2026 (ver LOG.md do projeto)
#
# ATENÇÃO: diferente dos anos 2017-2024 (Latin-1), os CSVs de 2025 e 2026 já vêm
# em UTF-8 da ANEEL — confirmado via inspeção de bytes crus (23/08/2026, ver
# CLAUDE.md "Lacuna de dados"). Ler com locale(encoding = "latin1") aqui corrompe
# todo nome acentuado (ex.: "PARNAÍBA" virava "PARNAABA"). Usar UTF-8.

library(readr)
library(here)

raw <- here("raw", "interrup_energia")

ap25 <- read_csv2(file.path(raw, "raw", "interrupcoes-energia-eletrica-2025.csv"), locale = locale(encoding = "UTF-8"))
saveRDS(ap25, file.path(raw, "interrupcoes-energia-eletrica-2025.rds"))
cat("2025 OK -", nrow(ap25), "linhas\n")
rm(ap25)
gc()

ap26 <- read_csv2(file.path(raw, "raw", "interrupcoes-energia-eletrica-2026.csv"), locale = locale(encoding = "UTF-8"))
saveRDS(ap26, file.path(raw, "interrupcoes-energia-eletrica-2026.rds"))
cat("2026 OK -", nrow(ap26), "linhas\n")
rm(ap26)
gc()
