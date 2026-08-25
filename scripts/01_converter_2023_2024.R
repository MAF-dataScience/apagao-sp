# Atualização dos RDS brutos ANEEL 2023/2024 para RDS
# Gerado em 23/08/2026 (ver LOG.md do projeto)
#
# MOTIVO: os RDS antigos de 2023 e 2024 (raw/interrup_energia/interrupcoes-energia-eletrica-2023.rds
# e -2024.rds) foram baixados em 01/12/2023 e 11/11/2024 respectivamente — ou
# seja, ANTES de cada ano terminar — e cobriam só até 31/10 daquele ano
# (nacional, não só SP). Ninguém tinha percebido porque o buraco só apareceu
# quando o gráfico de série mensal foi rodado pela primeira vez ponta-a-ponta
# (ver CLAUDE.md). ANEEL regenerou os extratos anuais em 2026-07-24
# (campo DatGeracaoConjuntoDados no CSV) — os arquivos baixados agora cobrem
# o ano completo.
#
# ATENÇÃO — mudança de encoding: diferente do que o CLAUDE.md registrava
# (2017-2024 em Latin-1), os CSVs regenerados por ANEEL em 2026-07/08 vêm em
# UTF-8, igual 2025/2026 — confirmado via inspeção de bytes crus (23/08/2026).
# Aparentemente a ANEEL padronizou pra UTF-8 em toda a série ao reprocessar.
# Ler com locale(encoding = "latin1") aqui corrompe nome acentuado.

library(readr)
library(here)

raw <- here("raw", "interrup_energia")

ap23 <- read_csv2(file.path(raw, "raw", "interrupcoes-energia-eletrica-2023.csv"), locale = locale(encoding = "UTF-8"))
saveRDS(ap23, file.path(raw, "interrupcoes-energia-eletrica-2023.rds"))
cat("2023 OK -", nrow(ap23), "linhas - range:", as.character(range(ap23$DatInicioInterrupcao, na.rm = TRUE)), "\n")
rm(ap23)
gc()

ap24 <- read_csv2(file.path(raw, "raw", "interrupcoes-energia-eletrica-2024.csv"), locale = locale(encoding = "UTF-8"))
saveRDS(ap24, file.path(raw, "interrupcoes-energia-eletrica-2024.rds"))
cat("2024 OK -", nrow(ap24), "linhas - range:", as.character(range(ap24$DatInicioInterrupcao, na.rm = TRUE)), "\n")
rm(ap24)
gc()
