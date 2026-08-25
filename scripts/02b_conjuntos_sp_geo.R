# Geometria dos conjuntos elétricos de SP (capital), pronta pra mapa
# Gerado em 23/08/2026 — usado pelo site (site/) pra evitar recalcular a
# interseção geoespacial toda vez que o relatório é renderizado.
#
# Mesma lógica de filtro geográfico do scripts/03_montar_base_sampa.R (corte
# em >50% de área de interseção com o município de SP + inclusão manual do
# conjunto VARGINHA) — mantida em sincronia manual com aquele script.

suppressPackageStartupMessages({
  library(sf)
  library(here)
})

conjuntos <- read_sf(here("raw", "interrup_energia", "ENEL_SP_390_2022-12-31_V11_20231001-2204.gdb.zip"), layer = "CONJ")

# workaround do bug do geobr::read_municipality() — ver nota em scripts/03_montar_base_sampa.R
municipio_sp_path <- here("raw", "geobr", "municipio_sp_2022.gpkg")
if (!file.exists(municipio_sp_path)) {
  dir.create(dirname(municipio_sp_path), recursive = TRUE, showWarnings = FALSE)
  download.file(
    "https://github.com/ipeaGIT/geobr/releases/download/v1.7.0/35municipality_2022_simplified.gpkg",
    municipio_sp_path, mode = "wb"
  )
}
mapasp <- read_sf(municipio_sp_path) |> subset(code_muni == 3550308)

apw <- st_intersects(conjuntos, mapasp)
apw <- which(lengths(apw) > 0)
conjuntos$sp <- NA
conjuntos$sp[apw] <- TRUE
apo <- conjuntos[!is.na(conjuntos$sp) & conjuntos$sp, ]

interseccao <- st_intersection(conjuntos, mapasp)
area_interseccao <- st_area(interseccao)
area2 <- st_area(apo)
aporc <- as.numeric(area_interseccao / area2) > 0.5
apo$sp <- aporc
apo$sp[apo$NOME == "VARGINHA"] <- TRUE
conjuntos_sp_geo <- apo[apo$sp, c("COD_ID", "NOME")]

saveRDS(conjuntos_sp_geo, here("bases", "conjuntos_sp_geo.rds"))
cat("Salvo bases/conjuntos_sp_geo.rds —", nrow(conjuntos_sp_geo), "conjuntos\n")
