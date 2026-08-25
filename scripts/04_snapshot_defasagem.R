# Snapshot de verificação de defasagem/revisão
# Criado em 23/08/2026, a pedido de Marco — construir prova ao longo do tempo
# de que a ANEEL NÃO revisa/atualiza retroativamente um mês já publicado
# (hipótese testada nesta sessão comparando jun/2025 vs jun/2026, ver LOG.md;
# evidência a favor, mas baseada em UM snapshot só — isso aqui é o mecanismo
# pra acumular snapshots reais e confirmar de verdade).
#
# Rodar este script de novo em sessões futuras (ex. a cada rebaixada de dado
# novo da ANEEL) — ele SÓ ACRESCENTA linhas ao arquivo, nunca sobrescreve
# snapshots antigos. Depois de duas ou mais datas de snapshot cobrindo o mesmo
# ano/mês, dá pra comparar `n_interrupcoes` entre elas: se o número mudar,
# houve revisão retroativa; se não mudar, a hipótese de "publicado = final"
# se confirma.

library(dplyr)
library(here)
library(readr)

base <- readRDS(here("bases", "interrupcoes-energia-sampa-2018-2026.rds"))

snapshot_novo <- base |>
  group_by(NumAno, mes_inicio) |>
  summarise(n_interrupcoes = n(), .groups = "drop") |>
  transmute(
    data_snapshot = Sys.Date(),
    ano_dado = NumAno,
    mes_dado = mes_inicio,
    n_interrupcoes
  )

caminho <- here("bases", "monitoramento_defasagem.csv")

if (file.exists(caminho)) {
  existente <- read_csv(caminho, show_col_types = FALSE, col_types = cols(data_snapshot = col_date()))
  existente <- existente |> filter(data_snapshot != Sys.Date())  # não duplicar snapshot do mesmo dia
  saida <- bind_rows(existente, snapshot_novo)
} else {
  saida <- snapshot_novo
}

saida <- saida |> arrange(data_snapshot, ano_dado, mes_dado)
write_csv(saida, caminho)

cat("Snapshot de", format(Sys.Date()), "salvo em bases/monitoramento_defasagem.csv —",
    nrow(snapshot_novo), "meses registrados,", n_distinct(saida$data_snapshot), "data(s) de snapshot no total.\n")
