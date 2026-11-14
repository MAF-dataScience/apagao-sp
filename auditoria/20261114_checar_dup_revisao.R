# (1) 2025 novo: linhas SP dobradas são duplicata exata da versão atual?
# (2) 2026 novo: jan-jul igual ao extrato anterior? duplicatas?
library(arrow); library(dplyr); library(here)
raw <- here("raw", "interrup_energia"); stg <- file.path(raw, "download_20261114", "parquet_staging")
le <- function(p, col) open_dataset(p) |> filter(grepl("ELETROPAULO|ENEL SP|Enel SP", .data[[col]])) |> collect()

n25 <- le(file.path(stg, "interrupcoes-energia-eletrica-2025.parquet"), "NomAgenteRegulado")
o25 <- le(file.path(raw, "parquet", "interrupcoes-energia-eletrica-2025.parquet"), "NomAgenteRegulado")
cat("2025 nova:", nrow(n25), "| distintas:", nrow(distinct(n25)), "| atual:", nrow(o25), "| distintas atual:", nrow(distinct(o25)), "\n")
cat("2025 distintas nova == distintas atual (anti_join nos dois sentidos):",
    nrow(anti_join(distinct(n25), distinct(o25), by = names(o25))), nrow(anti_join(distinct(o25), distinct(n25), by = names(o25))), "\n")
cat("DatGeracao 2025 nova:", paste(unique(n25$DatGeracaoConjuntoDados), collapse = ", "), "\n")
# nacional
nn <- open_dataset(file.path(stg, "interrupcoes-energia-eletrica-2025.parquet"))
cat("2025 nacional por DatGeracao:\n"); print(nn |> count(DatGeracaoConjuntoDados) |> collect())

n26 <- le(file.path(stg, "interrupcoes-energia-eletrica-2026.parquet"), "NomAgente")
o26 <- le(file.path(raw, "parquet", "interrupcoes-energia-eletrica-2026.parquet"), "NomAgente")
cat("2026 nova:", nrow(n26), "| distintas:", nrow(distinct(n26)), "| CodInterrupcao unicos:", n_distinct(n26$CodInterrupcao), "\n")
n26_jj <- n26 |> filter(DatInicioInterrupcao < as.POSIXct("2026-08-01", tz = "UTC"))
cmp <- setdiff(names(o26), "DatGeracaoConjuntoDados")
cat("2026 jan-jul nova:", nrow(n26_jj), "| atual:", nrow(o26),
    "| so na nova:", nrow(anti_join(n26_jj, o26, by = cmp)), "| so na atual:", nrow(anti_join(o26, n26_jj, by = cmp)), "\n")
print(n26 |> mutate(m = format(DatInicioInterrupcao, "%Y-%m")) |> count(m))
