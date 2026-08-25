# APAGAO SP - Densidade de UC por alimentador (24/08/2026)
# Marco Antonio Faganello - marcofaga@gmail.com
#
# Contexto: video time-lapse (CLAUDE.md, "Proximos passos" item 6). O
# alimentador do sul (ex: PARELHEIROS, VARGINHA) cobre area muito maior que
# um alimentador denso do centro - destacar uma fracao do COMPRIMENTO FISICO
# da linha proporcional a UC atingidas superestima visualmente area rural
# esparsa (uma fracao pequena da linha ainda cobre varios km). Achado de
# Marco ao ver o primeiro teste: um alimentador em Parelheiros formava um
# emaranhado enorme na tela.
#
# Correcao: em vez de proporcao por distancia, usar densidade real de UC.
# Constroi 2 bases:
#   - bases/alimentadores_total_uc.rds: total de UC cadastradas por
#     alimentador (UCBT_tab agrupado por CTMT) - denominador real (tambem
#     serve para criterio de piso por PROPORCAO, discutido com Marco).
#   - bases/alimentadores_pontos_uc.rds: coordenadas de cada UC do
#     alimentador (cadeia validada em 24/08/2026 mais cedo:
#     UCBT_tab.RAMAL -> RAMLIG.COD_ID -> RAMLIG.PN_CON_1 -> PONNOT.COD_ID).
#     No render, um evento sorteia um epicentro entre esses pontos e usa a
#     DENSIDADE local (raio que engloba as N UCs mais proximas) para
#     calibrar o trecho da linha a destacar - nunca afirma "esta casa
#     especifica", so calibra tamanho de area por densidade real.
#
# Nao roda em loop de frame - e cache, roda 1x (ou quando o .gdb atualizar).

library(here)
library(dplyr)
library(sf)

sf_use_s2(FALSE)

base <- readRDS(here("bases", "interrupcoes-energia-sampa-2018-2026.rds"))
codigos <- base |>
  filter(!is.na(DscAlimentadorSubestacao)) |>
  mutate(alim_cod = gsub(" ", "", DscAlimentadorSubestacao)) |>
  pull(alim_cod) |>
  unique()
cat("Alimentadores alvo:", length(codigos), "\n")

gdb <- here("raw", "interrup_energia", "ENEL_SP_390_2022-12-31_V11_20231001-2204.gdb.zip")
codigos_sql <- paste(sprintf("'%s'", codigos), collapse = ",")

# 1) posicao de cada UC do alimentador (cadeia RAMAL->RAMLIG->PONNOT) --------
# (GROUP BY via OGR SQL falhou no driver FileGDB - conta feita em R abaixo)
t <- Sys.time()
uc_ramal <- read_sf(gdb, query = sprintf(
  "SELECT RAMAL, CTMT FROM UCBT_tab WHERE CTMT IN (%s)", codigos_sql
)) |> st_drop_geometry()
cat("UCBT_tab (RAMAL, CTMT):", nrow(uc_ramal), "linhas -",
    round(as.numeric(difftime(Sys.time(), t, units = "secs")), 1), "s\n")

# total de UC por alimentador (denominador real) - contagem em R
alimentadores_total_uc <- table(uc_ramal$CTMT)
alimentadores_total_uc <- setNames(as.integer(alimentadores_total_uc), names(alimentadores_total_uc))
saveRDS(alimentadores_total_uc, here("bases", "alimentadores_total_uc.rds"))
cat("Totais de UC por alimentador:", length(alimentadores_total_uc), "alimentadores\n")

t <- Sys.time()
ramlig <- read_sf(gdb, query = sprintf(
  "SELECT COD_ID, PN_CON_1 FROM RAMLIG WHERE CTMT IN (%s)", codigos_sql
)) |> st_drop_geometry()
cat("RAMLIG:", nrow(ramlig), "linhas -", round(as.numeric(difftime(Sys.time(), t, units = "secs")), 1), "s\n")

t <- Sys.time()
ponnot <- read_sf(gdb, query = "SELECT COD_ID FROM PONNOT")
coords_ponnot <- st_coordinates(ponnot)
ponnot_df <- data.frame(COD_ID = ponnot$COD_ID, X = coords_ponnot[, 1], Y = coords_ponnot[, 2])
cat("PONNOT (todos, pra join em R):", nrow(ponnot_df), "linhas -",
    round(as.numeric(difftime(Sys.time(), t, units = "secs")), 1), "s\n")

t <- Sys.time()
uc_geo <- uc_ramal |>
  inner_join(ramlig, by = c("RAMAL" = "COD_ID")) |>
  inner_join(ponnot_df, by = c("PN_CON_1" = "COD_ID")) |>
  filter(!is.na(X))
cat(sprintf("UCs com geometria: %d de %d (%.1f%%) -", nrow(uc_geo), nrow(uc_ramal),
            100 * nrow(uc_geo) / nrow(uc_ramal)), round(as.numeric(difftime(Sys.time(), t, units = "secs")), 1), "s\n")

alimentadores_pontos_uc <- lapply(split(uc_geo[, c("X", "Y")], uc_geo$CTMT), as.matrix)

saveRDS(alimentadores_pontos_uc, here("bases", "alimentadores_pontos_uc.rds"))
cat("Salvo bases/alimentadores_pontos_uc.rds -", length(alimentadores_pontos_uc), "alimentadores\n")
cat("Salvo bases/alimentadores_total_uc.rds -", length(alimentadores_total_uc), "alimentadores\n")
