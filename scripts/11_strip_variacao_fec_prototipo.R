# APAGAO SP - Prototipo de strip plot: variacao da FEC por conjunto eletrico,
# jan-jul 2026 vs. media historica leave-one-out do mesmo periodo (mesma conta
# por tras da manchete de julho/2026 - "69 de 97 conjuntos acima da media").
# Nao integrado ao site ainda - so prototipo, ver CLAUDE.md secao "Proximos passos".
# Marco Antonio Faganello - marcofaga@gmail.com

library(tidyverse)
library(here)
library(plotly)
library(htmlwidgets)

conj <- readr::read_csv(here("bases", "dec_fec_mensal_conjunto.csv"), show_col_types = FALSE)

# fec_periodo: FEC agregado jan-jul por conjunto-ano (soma unidades_atingidas /
# media de consumidores_conjunto no periodo) - mesma logica ja usada e validada
# em sessao anterior (verificacao da manchete de julho/2026).
fec_periodo <- conj |>
  filter(mes_inicio <= 7) |>
  group_by(IdeConjuntoUnidadeConsumidora, DscConjuntoUnidadeConsumidora, NumAno) |>
  summarise(unidades_atingidas = sum(unidades_atingidas),
            consumidores_conjunto = mean(consumidores_conjunto),
            .groups = "drop") |>
  mutate(FEC_periodo = unidades_atingidas / consumidores_conjunto)

# Media historica leave-one-out (exclui o proprio 2026) + % de variacao.
variacao <- fec_periodo |>
  group_by(IdeConjuntoUnidadeConsumidora, DscConjuntoUnidadeConsumidora) |>
  group_modify(~{
    df <- .x
    if (!2026 %in% df$NumAno) return(tibble())
    fec_2026 <- df$FEC_periodo[df$NumAno == 2026]
    outros <- df$FEC_periodo[df$NumAno != 2026]
    tibble(FEC_2026 = fec_2026, FEC_media_historica = mean(outros),
           n_anos_base = length(outros))
  }) |>
  ungroup() |>
  mutate(pct_variacao = (FEC_2026 / FEC_media_historica - 1) * 100,
         acima = pct_variacao > 0)

cat(sprintf("Conjuntos no grafico: %d (%d acima da media, %d abaixo)\n",
            nrow(variacao), sum(variacao$acima), sum(!variacao$acima)))

# Jitter vertical determinístico (seed fixa) - eixo Y nao representa nenhuma
# variavel, so espalha os pontos pra nao empilhar exatamente na mesma linha.
set.seed(42)
variacao <- variacao |> mutate(jitter_y = runif(n(), -1, 1))

# Paleta: laranja da marca (acima da media) <-> azul (abaixo), cinza no zero -
# validado via skill dataviz (validate_palette.js "#e66101,#2a78d6"): todos os
# checks passam (CVD normal-vision Delta E 34.4, bem acima do piso de 15).
cor_acima <- "#e66101"
cor_abaixo <- "#2a78d6"

p <- variacao |>
  mutate(cor = ifelse(acima, cor_acima, cor_abaixo),
         label = str_to_title(DscConjuntoUnidadeConsumidora)) |>
  plot_ly(
    x = ~pct_variacao, y = ~jitter_y,
    type = "scatter", mode = "markers",
    marker = list(color = ~cor, size = 10, opacity = 0.75,
                  line = list(color = "rgba(255,255,255,0.6)", width = 1)),
    text = ~sprintf("%s<br>FEC jan-jul 2026: %.2f<br>Média histórica: %.2f<br>Variação: %+.0f%%",
                     label, FEC_2026, FEC_media_historica, pct_variacao),
    hovertemplate = "%{text}<extra></extra>"
  ) |>
  layout(
    xaxis = list(title = "Variação da FEC (jan-jul 2026 vs. média histórica do mesmo período)",
                 ticksuffix = "%", zeroline = FALSE, showgrid = TRUE, gridcolor = "#e1e0d9"),
    yaxis = list(title = "", showticklabels = FALSE, showgrid = FALSE,
                 zeroline = FALSE, range = c(-2.5, 2.5), fixedrange = TRUE),
    shapes = list(list(type = "line", x0 = 0, x1 = 0, y0 = -2.5, y1 = 2.5,
                        line = list(color = "#898781", width = 1, dash = "dot"))),
    margin = list(t = 10, l = 10),
    showlegend = FALSE
  ) |>
  config(displayModeBar = FALSE)

dir.create(here("graficos"), showWarnings = FALSE)
saveWidget(p, here("graficos", "prototipo_strip_variacao_fec.html"), selfcontained = TRUE)
cat("Salvo em graficos/prototipo_strip_variacao_fec.html\n")
