# APAGAO SP - Cache de coordenadas de alimentador para renderizacao rapida
# Marco Antonio Faganello - marcofaga@gmail.com
#
# Contexto (24/08/2026): construcao do video time-lapse de apagoes (ver
# CLAUDE.md, "Proximos passos" item 6). Renderizar o traçado de um
# alimentador via sf/GEOS a cada frame e caro demais para um video de
# milhares de frames - testado e descartado dois caminhos:
#   - plot(sf) direto no SSDMT bruto (~1000 segmentos/alimentador): ~4-13s/frame
#   - dissolver por CTMT via st_union antes de plotar: ainda pior (~2-11s/
#     frame) - unir segmentos que nao compartilham vertice exato com
#     sf_use_s2(FALSE) em lon/lat faz o GEOS renodar tudo, gerando
#     geometria MAIS complexa, nao mais simples.
# Solucao: extrair as coordenadas cruas 1x (fora de qualquer loop de
# frame) em matrizes x/y por alimentador, com linha de NA separando
# segmentos que nao se tocam (truque padrao do R base para desenhar
# varias polilinhas numa unica chamada de lines()). No loop de frame,
# so lines() e chamado - sem sf/GEOS - testado em ~0.7s para desenhar
# TODOS os alimentadores de uma vez (era ~9-11s so pra alguns poucos
# antes desse cache).
#
# Este script roda 1x (ou quando o .gdb da BDGD for atualizado) e salva
# bases/alimentadores_sp_coords.rds - uma lista nomeada por codigo de
# alimentador normalizado (sem espaco, batendo com
# gsub(" ", "", DscAlimentadorSubestacao) do dado de interrupcao),
# cada elemento uma matriz 2 colunas (X, Y) pronta pra lines().

library(here)
library(dplyr)
library(sf)

sf_use_s2(FALSE) # so desenho, nao precisa de precisao geodesica

base <- readRDS(here("bases", "interrupcoes-energia-sampa-2018-2026.rds"))
codigos <- base |>
  filter(!is.na(DscAlimentadorSubestacao)) |>
  mutate(alim_cod = gsub(" ", "", DscAlimentadorSubestacao)) |>
  pull(alim_cod) |>
  unique()

cat("Alimentadores distintos na base de interrupcao:", length(codigos), "\n")

gdb <- here("raw", "interrup_energia", "ENEL_SP_390_2022-12-31_V11_20231001-2204.gdb.zip")
codigos_sql <- paste(sprintf("'%s'", codigos), collapse = ",")
ssdmt_raw <- read_sf(gdb, query = sprintf("SELECT COD_ID, CTMT FROM SSDMT WHERE CTMT IN (%s)", codigos_sql))

encontrados <- unique(ssdmt_raw$CTMT)
cat(sprintf("Geometria encontrada na BDGD: %d de %d (%.1f%%)\n",
            length(encontrados), length(codigos), 100 * length(encontrados) / length(codigos)))
cat("Nao encontrados (primeiros 20):\n")
print(head(setdiff(codigos, encontrados), 20))

alimentadores_coords <- lapply(split(ssdmt_raw, ssdmt_raw$CTMT), function(g) {
  cc <- st_coordinates(g)
  m <- cc[, c("X", "Y")]
  partes <- split(seq_len(nrow(m)), cumsum(c(1, diff(cc[, "L1"]) != 0)))
  do.call(rbind, lapply(partes, function(ix) rbind(m[ix, , drop = FALSE], c(NA, NA))))
})

saveRDS(alimentadores_coords, here("bases", "alimentadores_sp_coords.rds"))
cat("Salvo em bases/alimentadores_sp_coords.rds -", length(alimentadores_coords), "alimentadores\n")
