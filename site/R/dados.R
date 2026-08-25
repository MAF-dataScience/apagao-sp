# Preparo de dados compartilhado pelas páginas do site (Apagão-SP)
# Lê a base processada do projeto (bases/interrupcoes-energia-sampa-2018-2025.rds)
# e monta os objetos que cada .qmd usa. Não editar dados aqui — só reshape.

suppressPackageStartupMessages({
  library(dplyr)
  library(here)
  library(lubridate)
  library(sf)
})

meses_pt <- c("janeiro", "fevereiro", "março", "abril", "maio", "junho",
              "julho", "agosto", "setembro", "outubro", "novembro", "dezembro")

# Taxonomia de causa (causa_04, nível mais granular) reagrupada em 25/08/2026
# a pedido de Marco - o nível causa_03 (4 categorias) escondia que "Falha de
# equipamento" e "Vento e árvore/vegetação" sao o grosso do total, com peso
# bem diferente das outras causas dentro de cada "guarda-chuva" original.
# "Vento" e "Árvore ou vegetação" foram unidas deliberadamente: sao codigos
# mutuamente exclusivos no proprio microdado da ANEEL (o tecnico da
# distribuidora escolhe um ou outro), sem campo de texto livre que permita
# saber se um evento de "vento" na verdade foi uma arvore caindo por causa
# do vento - nao da pra separar as duas com o dado que temos, entao juntar
# e mais honesto que fingir uma distincao que nao conseguimos comprovar.
# Categorias residuais pequenas (<1% cada da serie toda) viram "Outros".
mapear_causa_final <- function(causa_03, causa_04) {
  dplyr::case_when(
    causa_03 == "PROPRIAS DO SISTEMA" & causa_04 == "FALHA DE MATERIAL OU EQUIPAMENTO" ~ "Falha de equipamento",
    causa_03 == "PROPRIAS DO SISTEMA" & causa_04 == "SOBRECARGA" ~ "Sobrecarga",
    causa_03 == "MEIO AMBIENTE" & causa_04 %in% c("ARVORE OU VEGETACAO", "VENTO") ~ "Árvore/vegetação e vento",
    causa_03 == "TERCEIROS" ~ "Terceiros",
    causa_03 == "FALHA OPERACIONAL" ~ "Falha operacional",
    TRUE ~ "Outros"
  )
}

# NOTA: here() resolve a raiz em site/ (o próprio _quarto.yml é reconhecido
# como sentinela de projeto), não na raiz do projeto R (2410_interrupcao_sp.Rproj,
# um nível acima) — por isso o ".." aqui, em vez do here() "puro" usado no
# resto do pipeline (scripts/01-03).
base <- readRDS(here("..", "bases", "interrupcoes-energia-sampa-2018-2026.rds"))
geo  <- readRDS(here("..", "bases", "conjuntos_sp_geo.rds"))
dec_fec_sp <- readRDS(here("..", "bases", "dec_fec_mensal_sp.rds"))
distritos_geo <- read_sf(here("..", "raw", "geobr", "distritos_sp_2010.gpkg"))
alimentador_distrito_pct <- readRDS(here("..", "bases", "alimentador_distrito_pct.rds"))

# Série mensal agregada (toda a série, usada no gráfico histórico e no destaque do mês) ====
serie_mensal <- base |>
  group_by(NumAno, mes_inicio) |>
  summarise(
    n = n(),
    unidades_atingidas = sum(NumUnidadeConsumidora, na.rm = TRUE),
    prop_media = mean(prop_atingidas, na.rm = TRUE),
    # duração média PONDERADA por UC atingida (soma(UC*h)/soma(UC)), não a
    # média simples por evento (1 evento = 1 peso, não importa o tamanho).
    # Achado de Marco, 25/08/2026: a média simples (~4,1h em jun/2026) não
    # responde "quanto tempo, em média, uma unidade atingida ficou sem
    # energia" — responde "quanto dura um evento típico", enviesado pelos
    # inúmeros eventos de 1 UC que ficam horas sem reparo (baixa
    # prioridade). A ponderada (~1,55h em jun/2026) é mais baixa porque
    # eventos grandes tendem a ser resolvidos mais rápido (prioridade da
    # concessionária) — puxam a média pra baixo quando pesados por UC.
    horas_media = sum(NumUnidadeConsumidora * total_horas, na.rm = TRUE) / sum(NumUnidadeConsumidora, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(data = as.Date(sprintf("%d-%02d-01", NumAno, mes_inicio))) |>
  arrange(data) |>
  mutate(media_movel_12m = as.numeric(stats::filter(n, rep(1 / 12, 12), sides = 1)))

# Série mensal por causa (nível causa_03) - "Meio ambiente" vs. "Próprias do
# sistema", usada na 2a aba do gráfico histórico (pedido de Marco,
# 25/08/2026 - explorar se a fatia climática vem crescendo ao longo dos anos)
serie_causas <- base |>
  filter(causa_03 %in% c("MEIO AMBIENTE", "PROPRIAS DO SISTEMA")) |>
  group_by(NumAno, mes_inicio, causa_03) |>
  summarise(n = n(), .groups = "drop") |>
  mutate(
    data = as.Date(sprintf("%d-%02d-01", NumAno, mes_inicio)),
    causa_label = ifelse(causa_03 == "MEIO AMBIENTE", "Meio ambiente", "Próprias do sistema")
  ) |>
  arrange(data) |>
  group_by(causa_label) |>
  mutate(media_movel_12m = as.numeric(stats::filter(n, rep(1 / 12, 12), sides = 1))) |>
  ungroup()

# Mês de referência = mês mais recente com dado na base (não o mês corrente do calendário —
# a fonte tem defasagem de publicação, ver página de Metodologia) ====
mes_ref_row <- serie_mensal |> slice_max(data, n = 1)
mes_ref_data <- mes_ref_row$data
ano_ref <- mes_ref_row$NumAno
mes_ref <- mes_ref_row$mes_inicio
mes_ref_label <- paste(meses_pt[mes_ref], ano_ref)

mes_anterior_row <- serie_mensal |> filter(data == mes_ref_data %m-% months(1))
mes_ano_passado_row <- serie_mensal |> filter(data == mes_ref_data %m-% years(1))

variacao_pct <- function(atual, comparacao) {
  if (length(comparacao) == 0 || length(atual) == 0) return(NA_real_)
  if (is.na(comparacao) || comparacao == 0) return(NA_real_)
  (atual - comparacao) / comparacao * 100
}

kpi <- list(
  numero_interrupcoes = mes_ref_row$n,
  unidades_atingidas  = mes_ref_row$unidades_atingidas,
  prop_media          = mes_ref_row$prop_media,
  horas_media         = mes_ref_row$horas_media,
  var_mes_anterior    = variacao_pct(mes_ref_row$n, mes_anterior_row$n),
  var_ano_passado     = variacao_pct(mes_ref_row$n, mes_ano_passado_row$n),
  var_unidades_ano_passado = variacao_pct(mes_ref_row$unidades_atingidas, mes_ano_passado_row$unidades_atingidas)
)

# Índice Apagão-SP (DEC normalizado, base 100 = média histórica do mesmo mês
# calendário — decisão de 23/08/2026, ver bases/METODOLOGIA_DEC_FEC.md).
# Comparar sempre o mesmo mês entre anos evita dois problemas de uma vez:
# sazonalidade (sem precisar de média móvel) e o artefato de comparar ano
# parcial (2026) contra ano cheio (achado de 24/08/2026 na mesma nota).
dec_fec_sp <- dec_fec_sp |>
  mutate(data = as.Date(sprintf("%d-%02d-01", NumAno, mes_inicio))) |>
  arrange(data)

# média histórica exclui o próprio ano-mês sendo comparado (leave-one-out) —
# "média histórica do mesmo mês" deve significar "outros anos", não incluir
# a si mesma, especialmente com só 8-9 anos de série (autoinclusão pesaria
# ~11-12% no próprio número)
baseline_dec_mes <- dec_fec_sp |>
  group_by(mes_inicio) |>
  summarise(soma_dec = sum(DEC, na.rm = TRUE), n_anos_total = n(), .groups = "drop")

dec_fec_sp <- dec_fec_sp |>
  left_join(baseline_dec_mes, by = "mes_inicio") |>
  mutate(
    n_anos = n_anos_total - 1,
    dec_medio_historico = (soma_dec - DEC) / n_anos,
    indice_apagao_sp = DEC / dec_medio_historico * 100
  )

indice_mes_ref_row <- dec_fec_sp |> filter(NumAno == ano_ref, mes_inicio == mes_ref)

kpi$indice_apagao_sp <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$indice_apagao_sp else NA_real_
kpi$dec_mes_ref       <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$DEC else NA_real_
kpi$fec_mes_ref       <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$FEC else NA_real_
kpi$indice_n_anos_base <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$n_anos else NA_integer_

# Recorte só do mês de referência, usado no ranking/causas/mapa ====
base_mes <- base |> filter(NumAno == ano_ref, mes_inicio == mes_ref)

# Maior evento do mês (substitui "proporção média atingida" — média de uma
# distribuição de cauda longuíssima, pouco informativa: mediana real de
# prop_atingidas é 0,002%, ver DICIONARIO_DADOS.md. Tentativa 2, "conjuntos
# afetados no mês", também descartada: com 99 conjuntos e ~29 mil eventos/
# mês, a métrica satura perto do teto mesmo com pisos altos de magnitude —
# não varia o suficiente pra contar uma história mês a mês. Achados de
# Marco, 24/08/2026.) — este número nunca satura e sempre é concreto,
# complementa o ranking abaixo (que é por frequência, não por tamanho do
# maior evento isolado).
maior_evento_row <- base_mes |> slice_max(NumUnidadeConsumidora, n = 1, with_ties = FALSE)
kpi$maior_evento_uc       <- maior_evento_row$NumUnidadeConsumidora
kpi$maior_evento_conjunto <- stringr::str_to_title(maior_evento_row$DscConjuntoUnidadeConsumidora)

causas_mes <- base_mes |>
  mutate(causa_label = mapear_causa_final(causa_03, causa_04)) |>
  count(causa_label, sort = TRUE) |>
  mutate(pct = n / sum(n) * 100)

# Repartição de cada evento do mês entre distritos, ponderada por densidade
# real de UC do alimentador (não conjunto elétrico) - decisão de 25/08/2026,
# pedido de Marco, aplicada tanto ao mapa quanto ao ranking abaixo. O
# microdado de interrupção não tem distrito nativo, só conjunto/alimentador
# - crosswalk construído em scripts/09_alimentador_distrito_pct.R: cada
# alimentador reparte seus eventos entre os distritos que toca, na MESMA
# PROPORÇÃO da sua base real de clientes (não "tudo pro distrito
# dominante" - testado antes de decidir, ~19% dos alimentadores ficam
# genuinamente divididos entre distritos, então o método ingênuo erraria
# uma fatia real de casos). Contagens finais são fracionárias, não
# inteiras - são estimativas, não uma identificação exata de qual distrito
# cada evento pertence.
# Funções reaproveitadas pro ranking do mês E dos últimos 12 meses (pedido
# de Marco, 25/08/2026 - lado a lado na mesma seção, mesma janela de 12
# meses já usada na média móvel do gráfico histórico, pra manter a mesma
# linguagem analítica da página inteira).
montar_eventos_distrito <- function(base_periodo) {
  base_periodo |>
    filter(!is.na(DscAlimentadorSubestacao)) |>
    mutate(alim_cod = gsub(" ", "", DscAlimentadorSubestacao)) |>
    group_by(alim_cod) |>
    # uc_horas e uc_total separados (não a razão já pronta) - a média por
    # distrito soma os dois numeradores/denominadores antes de dividir,
    # nunca faz média das médias de cada alimentador (viés de Simpson,
    # mesmo cuidado já usado no DEC/FEC agregado do projeto)
    summarise(
      n_eventos = n(),
      uc_horas = sum(NumUnidadeConsumidora * total_horas, na.rm = TRUE),
      uc_total = sum(NumUnidadeConsumidora, na.rm = TRUE),
      .groups = "drop"
    ) |>
    inner_join(alimentador_distrito_pct, by = "alim_cod") |>
    mutate(n_distrito = n_eventos * pct, uc_horas_distrito = uc_horas * pct, uc_distrito = uc_total * pct)
}

montar_ranking_distrito <- function(eventos_distrito_df, n_top = 10) {
  eventos_distrito_df |>
    group_by(cod_distrito, nome_distrito) |>
    summarise(
      n = sum(n_distrito),
      horas_media = sum(uc_horas_distrito) / sum(uc_distrito),
      .groups = "drop"
    ) |>
    arrange(desc(n)) |>
    slice_head(n = n_top) |>
    transmute(
      Distrito = stringr::str_to_title(nome_distrito),
      `Interrupções` = round(n, 1),
      `Duração (h)` = round(horas_media, 1)
    )
}

eventos_distrito <- montar_eventos_distrito(base_mes)

mapa_contagem_distrito <- eventos_distrito |>
  group_by(cod_distrito) |>
  summarise(n = sum(n_distrito), .groups = "drop")

geo_mapa <- distritos_geo |>
  left_join(mapa_contagem_distrito, by = "cod_distrito") |>
  mutate(n = ifelse(is.na(n), 0, n))

ranking_mes <- montar_ranking_distrito(eventos_distrito)

# Últimos 12 meses (janela terminando no mês de referência, mesma janela
# usada em media_movel_12m) - dá o "quem sofre cronicamente", não só o
# retrato de um mês que pode ter sido puxado por 1 tempestade isolada.
base_12m <- base |>
  mutate(data_mes = as.Date(sprintf("%d-%02d-01", NumAno, mes_inicio))) |>
  filter(data_mes >= (mes_ref_data %m-% months(11)), data_mes <= mes_ref_data)

eventos_distrito_12m <- montar_eventos_distrito(base_12m)
ranking_12m <- montar_ranking_distrito(eventos_distrito_12m)

causas_12m <- base_12m |>
  mutate(causa_label = mapear_causa_final(causa_03, causa_04)) |>
  count(causa_label, sort = TRUE) |>
  mutate(pct = n / sum(n) * 100)
