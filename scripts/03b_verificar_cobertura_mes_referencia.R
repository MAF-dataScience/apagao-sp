# Checagem padrão pós-atualização mensal: confirma que o mês de referência
# (mês mais recente na base) tem cobertura até o último dia do mês, sem corte
# no meio. Motivação: já aconteceu antes de um extrato vir truncado (nov-dez
# de 2023/2024 paravam em 31/10 porque o RDS bruto tinha sido baixado antes do
# ano terminar — ver CLAUDE.md, seção "Lacuna de dados"). Rodar sempre depois
# de 03_montar_base_sampa.R, antes de seguir com DEC/FEC e publicação do site.

library(here)
library(dplyr)
library(lubridate)

base <- readRDS(here("bases", "interrupcoes-energia-sampa-2018-2026.rds"))

mes_ref_row <- base |>
  count(NumAno, mes_inicio) |>
  slice_max(NumAno * 100 + mes_inicio, n = 1)

ano_ref <- mes_ref_row$NumAno
mes_ref <- mes_ref_row$mes_inicio

cat("Mês de referência detectado:", mes_ref, "/", ano_ref, "\n\n")

ref <- base |> filter(NumAno == ano_ref, mes_inicio == mes_ref)

ultimo_dia_mes <- ceiling_date(ymd(paste(ano_ref, mes_ref, "01")), "month") - days(1)

data_min <- min(ref$DatInicioInterrupcao)
data_max <- max(ref$DatInicioInterrupcao)

cat("Data mínima:", as.character(data_min), "\n")
cat("Data máxima:", as.character(data_max), "\n")
cat("Último dia esperado do mês:", as.character(ultimo_dia_mes), "\n\n")

if (as.Date(data_max) < ultimo_dia_mes) {
  cat(
    "*** ALERTA: dado máximo não chega no último dia do mês —",
    as.numeric(ultimo_dia_mes - as.Date(data_max)),
    "dia(s) faltando. Mês pode estar truncado — não fechar essa edição sem investigar. ***\n"
  )
} else {
  cat("OK: cobertura chega até o último dia do mês.\n")
}

cat("\nContagem diária dos últimos 5 dias do mês de referência:\n")
contagem_fim <- ref |>
  mutate(dia = as.Date(DatInicioInterrupcao)) |>
  count(dia) |>
  filter(dia >= ultimo_dia_mes - days(4)) |>
  arrange(dia)
print(contagem_fim, n = 10)

media_mes <- ref |> mutate(dia = as.Date(DatInicioInterrupcao)) |> count(dia) |> pull(n) |> mean()
cat("\nMédia diária do mês inteiro:", round(media_mes, 1), "\n")

ultimo_dia_n <- contagem_fim |> filter(dia == max(dia)) |> pull(n)
if (length(ultimo_dia_n) == 1 && ultimo_dia_n < media_mes * 0.3) {
  cat("*** ALERTA: contagem do último dia (", ultimo_dia_n, ") está bem abaixo da média diária do mês — possível corte, investigar antes de publicar. ***\n")
} else {
  cat("OK: contagem do último dia não indica corte abrupto.\n")
}

beepr::beep()
