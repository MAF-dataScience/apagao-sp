# APAGAO SP - Crosswalk alimentador -> distrito, ponderado por densidade real
# de UC (25/08/2026)
# Marco Antonio Faganello - marcofaga@gmail.com
#
# Contexto: o mapa "Onde as interrupcoes se concentraram" do site usava
# conjunto eletrico (divisao da propria distribuidora, 99 unidades) como
# unidade geografica. Marco pediu pra trocar pelos 96 distritos oficiais de
# SP - mas o microdado de interrupcao nao tem distrito nativo, so conjunto.
#
# Testado antes de decidir o metodo (a pedido de Marco, "vamos ver a
# realidade desse dado antes de decidir"): dos 1.121 alimentadores com UC
# geolocalizada, 60% tocam 2+ distritos, mas so ~19% tem menos de 70% das
# UCs no distrito dominante - ou seja, uma fatia real (nao desprezivel) dos
# alimentadores fica genuinamente dividida entre distritos.
#
# Metodo escolhido: cada alimentador reparte seus eventos entre distritos
# na MESMA PROPORCAO da sua base real de clientes (bases/alimentadores_pontos_uc.rds,
# 6,5M pontos de UC ja geolocalizados via UCBT_tab->RAMLIG->PONNOT, ver
# scripts/08_alimentadores_pontos_uc.R). Ex: alimentador com 700 UCs em
# Vila Mariana e 300 na Saude reparte qualquer evento seu 70%/30% entre os
# dois distritos, em vez de jogar o evento inteiro pro distrito onde o
# alimentador "esta mais" (que erraria a Saude pra zero).
#
# Ressalva que continua valendo (mesma linha etica do resto do projeto):
# ainda e estimativa - nao sabemos se as UCs de um evento especifico
# estavam mais concentradas de um lado ou outro, so a distribuicao geral
# dos clientes do alimentador.

library(here)
library(sf)
library(dplyr)

sf_use_s2(FALSE)

pontos_uc <- readRDS(here("bases", "alimentadores_pontos_uc.rds"))
distritos <- read_sf(here("raw", "geobr", "distritos_sp_2010.gpkg"))

todos_pontos <- do.call(rbind, lapply(names(pontos_uc), function(cod) {
  m <- pontos_uc[[cod]]
  data.frame(alim_cod = cod, X = m[, 1], Y = m[, 2])
}))
cat("Total de pontos de UC:", nrow(todos_pontos), "em", length(pontos_uc), "alimentadores\n")

pontos_sf <- st_as_sf(todos_pontos, coords = c("X", "Y"), crs = st_crs(distritos))
join <- st_join(pontos_sf, distritos[, c("nome_distrito", "cod_distrito")], join = st_intersects)
join_df <- st_drop_geometry(join)

n_fora <- sum(is.na(join_df$nome_distrito))
cat("Pontos fora de todos os distritos (nao entram no denominador):", n_fora,
    sprintf("(%.1f%%)\n", 100 * n_fora / nrow(join_df)))

# proporcao de UC de cada alimentador por distrito - denominador exclui
# pontos sem distrito (assume que sao o mesmo perfil de cliente, so um
# desalinhamento de borda entre a geometria da BDGD e o shapefile de
# distrito, nao um cliente genuinamente fora de SP)
alimentador_distrito_pct <- join_df |>
  filter(!is.na(nome_distrito)) |>
  count(alim_cod, nome_distrito, cod_distrito, name = "n_uc") |>
  group_by(alim_cod) |>
  mutate(pct = n_uc / sum(n_uc)) |>
  ungroup() |>
  arrange(alim_cod, desc(pct))

cat("\nAlimentadores no crosswalk final:", n_distinct(alimentador_distrito_pct$alim_cod), "\n")
cat("Checagem - soma de pct por alimentador (deve ser ~1):\n")
print(summary(alimentador_distrito_pct |> group_by(alim_cod) |> summarise(soma = sum(pct)) |> pull(soma)))

saveRDS(alimentador_distrito_pct, here("bases", "alimentador_distrito_pct.rds"))
write.csv(alimentador_distrito_pct, here("bases", "alimentador_distrito_pct.csv"), row.names = FALSE)
cat("\nSalvo bases/alimentador_distrito_pct.rds e .csv\n")
