# APAGAO SP - Protótipo de mapa por evento, nível de ponto de conexão da UC
# Marco Antonio Faganello - marcofaga@gmail.com
#
# Contexto (24/08/2026, ver CLAUDE.md "Próximos passos" itens 4 e 6, e LOG.md):
# investigação da granularidade geográfica disponível além de conjunto elétrico
# concluiu que dá pra chegar em dois níveis mais finos, ambos validados por
# match de código E por plausibilidade geográfica em escala (não só uma
# amostra — foi assim que se pegou um caminho errado, ver Nível 3 abaixo):
#
# - Nível 2 (alimentador, linha do circuito): CTMT -> SSDMT
# - Nível 3 (ponto de conexão de cada UC do alimentador):
#     UCBT_tab.RAMAL -> RAMLIG.COD_ID -> RAMLIG.PN_CON_1 -> PONNOT.COD_ID
#   (o caminho testado primeiro, UCBT_tab.UNI_TR_MT -> UNTRMT, tinha 100% de
#   match de código mas dispersão geográfica implausível em escala — mediana
#   de 69km por alimentador. Não usar esse campo pra geolocalização.)
#
# Este script é um PROTÓTIPO/MODELO — gera o mapa de UM evento (aleatório por
# padrão) pra visualizar o resultado. Não está integrado ao pipeline principal
# (03_montar_base_sampa.R) nem ao site ainda. Serve de base pra uma futura
# peça de mapa/vídeo da dinâmica dos apagões (visão registrada no CLAUDE.md,
# item 6) — ainda não é prioridade, decisão de escopo pendente com Marco.
#
# RESSALVA IMPORTANTE (manter em qualquer uso público deste mapa): ele mostra
# TODAS as UCs cadastradas no alimentador atingido (foto da BDGD, dez/2022),
# não literalmente as N unidades que a ANEEL contou como atingidas naquele
# evento específico — o microdado de interrupção nunca identifica qual UC
# individual foi afetada, só a contagem agregada (NumUnidadeConsumidora).

# libraries ====================================================================

library(sf)
library(dplyr)
library(ggplot2)
library(stringi)
library(here)

# helpers ========================================================================

normalizar <- function(x) stri_trans_general(toupper(trimws(x)), "Latin-ASCII")

# Carrega as coordenadas de PONNOT uma vez só (1,4M pontos) — reaproveitar essa
# tabela entre chamadas de gerar_mapa_evento() se for gerar vários mapas (ex.
# frames de um vídeo), em vez de reler a cada evento.
carregar_ponnot <- function(gdb) {
  ponnot <- read_sf(gdb, query = "SELECT COD_ID FROM PONNOT")
  coords <- st_coordinates(ponnot)
  data.frame(COD_ID = ponnot$COD_ID, lon = coords[, 1], lat = coords[, 2])
}

# Gera o mapa (ggplot) de um evento — `ev` é uma linha de
# bases/interrupcoes-energia-sampa-2018-2026.rds (precisa de
# DscConjuntoUnidadeConsumidora, DscAlimentadorSubestacao,
# DatInicioInterrupcao, DatFimInterrupcao, NumUnidadeConsumidora, total_horas,
# causa_03).
gerar_mapa_evento <- function(ev, gdb, ponnot_df, conjuntos_sp) {
  alimentador <- gsub(" ", "", ev$DscAlimentadorSubestacao)
  conjunto_nome <- ev$DscConjuntoUnidadeConsumidora

  # Nivel 2 - tracado do alimentador
  ssdmt <- read_sf(gdb, query = paste0("SELECT COD_ID, CTMT FROM SSDMT WHERE CTMT = '", alimentador, "'"))

  # Nivel 3 - pontos de conexao das UCs do alimentador
  ramlig <- st_drop_geometry(read_sf(gdb, query = paste0("SELECT COD_ID, PN_CON_1 FROM RAMLIG WHERE CTMT = '", alimentador, "'")))
  ramlig_geo <- ramlig |> left_join(ponnot_df, by = c("PN_CON_1" = "COD_ID")) |> filter(!is.na(lon))
  pontos_uc <- st_as_sf(ramlig_geo, coords = c("lon", "lat"), crs = 4674) # SIRGAS 2000

  # Nivel 1 - poligono do conjunto (contexto). Normalizar acento nos dois
  # lados — a base de interrupcao vem com acento ("HIPÓDROMO"), o shapefile
  # nao ("HIPODROMO"); sem isso o filtro nao bate e o poligono some (achado
  # de 24/08/2026, ao gerar o primeiro exemplo deste script).
  conj <- conjuntos_sp |> filter(normalizar(NOME) == normalizar(conjunto_nome))

  ggplot() +
    geom_sf(data = conj, fill = "grey96", color = "grey70", linewidth = 0.4) +
    geom_sf(data = ssdmt, color = "#5e3c99", linewidth = 0.5, alpha = 0.8) +
    geom_sf(data = pontos_uc, color = "#e66101", size = 0.3, alpha = 0.6) +
    labs(
      title = sprintf("Interrupção no conjunto %s (alimentador %s)", conjunto_nome, ev$DscAlimentadorSubestacao),
      subtitle = sprintf(
        "%s — %s UCs atingidas — %.0fmin de duração — causa: %s",
        format(ev$DatInicioInterrupcao, "%d/%m/%Y %H:%M"),
        format(ev$NumUnidadeConsumidora, big.mark = ".", decimal.mark = ","),
        ev$total_horas * 60,
        tolower(ev$causa_03)
      ),
      caption = paste(
        "Linha roxa = traçado do alimentador (SSDMT). Pontos laranja = ponto de conexão de cada UC do alimentador (RAMLIG->PONNOT).",
        "Ressalva: mostra todas as UCs do alimentador, não literalmente as atingidas nesse evento (ANEEL só informa a contagem).",
        "Fonte: ANEEL + BDGD Enel SP (dez/2022).",
        sep = "\n"
      )
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(size = 12, face = "bold"),
      plot.subtitle = element_text(size = 10),
      plot.caption = element_text(size = 7, hjust = 0)
    )
}

# demo ===========================================================================
# Exemplo de uso: sorteia um evento de 2026 (semente fixa p/ reprodutibilidade;
# piso de 50 UCs so pra garantir um mapa visualmente util como modelo, nao
# necessariamente o maior evento) e gera o mapa.

if (sys.nframe() == 0) {
  gdb <- here("raw", "interrup_energia", "ENEL_SP_390_2022-12-31_V11_20231001-2204.gdb.zip")

  base <- readRDS(here("bases", "interrupcoes-energia-sampa-2018-2026.rds"))
  set.seed(42)
  ev <- base |> filter(NumAno == 2026, NumUnidadeConsumidora >= 50) |> slice_sample(n = 1)
  cat("Evento sorteado:\n")
  print(as.data.frame(ev[, c("DscConjuntoUnidadeConsumidora", "DscAlimentadorSubestacao", "DatInicioInterrupcao", "NumUnidadeConsumidora", "total_horas")]))

  ponnot_df <- carregar_ponnot(gdb)
  conjuntos_sp <- readRDS(here("bases", "conjuntos_sp_geo.rds"))

  p <- gerar_mapa_evento(ev, gdb, ponnot_df, conjuntos_sp)

  out_dir <- here("graficos")
  dir.create(out_dir, showWarnings = FALSE)
  out <- file.path(out_dir, "modelo_mapa_evento.png")
  ggsave(out, p, width = 8, height = 6.5, dpi = 200)
  cat("Mapa salvo em:", out, "\n")

  beepr::beep()
}
