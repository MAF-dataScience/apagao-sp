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
# Excecao aberta em 10/09/2026 (pedido de Marco): "Desligamento para
# manutencao emergencial" ficava dentro de "Outros" apesar de ter virado
# manchete (triplicou jan-jul 2025->2026) - um leitor nao tinha como conferir
# essa causa especifica em nenhum grafico do site. Separada em categoria
# propria mesmo sendo <1% da serie toda (0,31%), porque no mes de referencia
# de julho/2026 ela sozinha (1,32%) ja supera o resto do balde "Outros"
# (0,49%) - o critério de "% da série toda" escondia um pico recente.
mapear_causa_final <- function(causa_03, causa_04) {
  dplyr::case_when(
    causa_03 == "PROPRIAS DO SISTEMA" & causa_04 == "FALHA DE MATERIAL OU EQUIPAMENTO" ~ "Falha de equipamento",
    causa_03 == "PROPRIAS DO SISTEMA" & causa_04 == "SOBRECARGA" ~ "Sobrecarga",
    causa_03 == "PROPRIAS DO SISTEMA" & causa_04 == "DESLIGAMENTO PARA MANUTENCAO EMERGENCIAL" ~ "Manutenção emergencial",
    causa_03 == "MEIO AMBIENTE" & causa_04 %in% c("ARVORE OU VEGETACAO", "VENTO") ~ "Árvore/vegetação e vento",
    causa_03 == "TERCEIROS" ~ "Terceiros",
    causa_03 == "FALHA OPERACIONAL" ~ "Falha operacional",
    TRUE ~ "Outros"
  )
}

# stringr::str_to_title() capitaliza toda palavra, inclusive preposições
# (ex. "Taboão Da Serra") — achado de Marco em 24/08/2026, corrigido em
# 10/09/2026. Título correto em português deixa preposição/artigo minúsculo,
# exceto quando é a primeira palavra do nome.
titulo_pt <- function(x) {
  preposicoes <- c("da", "de", "do", "das", "dos", "e")
  vapply(stringr::str_to_title(x), function(titulo) {
    palavras <- strsplit(titulo, " ")[[1]]
    if (length(palavras) > 1) {
      idx <- tolower(palavras[-1]) %in% preposicoes
      palavras[-1][idx] <- tolower(palavras[-1][idx])
    }
    paste(palavras, collapse = " ")
  }, character(1), USE.NAMES = FALSE)
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
  summarise(soma_dec = sum(DEC, na.rm = TRUE), soma_fec = sum(FEC, na.rm = TRUE),
            n_anos_total = n(), .groups = "drop")

dec_fec_sp <- dec_fec_sp |>
  left_join(baseline_dec_mes, by = "mes_inicio") |>
  mutate(
    n_anos = n_anos_total - 1,
    dec_medio_historico = (soma_dec - DEC) / n_anos,
    fec_medio_historico = (soma_fec - FEC) / n_anos,
    indice_apagao_sp = DEC / dec_medio_historico * 100
  )

indice_mes_ref_row <- dec_fec_sp |> filter(NumAno == ano_ref, mes_inicio == mes_ref)

kpi$indice_apagao_sp <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$indice_apagao_sp else NA_real_
kpi$dec_mes_ref       <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$DEC else NA_real_
kpi$fec_mes_ref       <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$FEC else NA_real_
kpi$indice_n_anos_base <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$n_anos else NA_integer_
kpi$dec_medio_historico_mes <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$dec_medio_historico else NA_real_
kpi$fec_medio_historico_mes <- if (nrow(indice_mes_ref_row) == 1) indice_mes_ref_row$fec_medio_historico else NA_real_

# FEC e DEC do mês de referência (julho) vs. média histórica do MESMO MÊS
# calendário (leave-one-out, já calculada acima pro Índice Apagão-SP) - aba
# nova do gráfico de série histórica (pedido de Marco, 10/09/2026). Trocado
# de "acumulado jan-mês de referência" pra "só o mês de referência" a pedido
# de Marco: o recorte mensal isolado mostra uma alta ainda maior (~+55% na
# FEC de julho vs. ~+37% no acumulado jan-jul) porque não dilui o pico do
# mês com os outros 6 meses do ano - ver LOG.md, sessão de 10/09/2026.
# FEC e DEC em painéis separados (small multiples) porque são escalas/
# unidades diferentes (nº de interrupções vs. horas) - nunca no mesmo eixo.
# Reescala pra unidade mais concreta pro leitor leigo (pedido de Marco,
# 10/09/2026: "0,2 ou 0,3 não diz muita coisa") - o cálculo por trás não
# muda, só a leitura: FEC x100 vira "interrupções a cada 100 UC" (0,275 ->
# 27,5); DEC x60 vira minutos em vez de horas (0,41h -> 24,6 min).
fec_mes_grafico <- tibble::tibble(
  categoria = c(sprintf("Média histórica (mesmo mês)"), mes_ref_label),
  valor = c(kpi$fec_medio_historico_mes, kpi$fec_mes_ref) * 100,
  destaque = c(FALSE, TRUE)
)

dec_mes_grafico <- tibble::tibble(
  categoria = c(sprintf("Média histórica (mesmo mês)"), mes_ref_label),
  valor = c(kpi$dec_medio_historico_mes, kpi$dec_mes_ref) * 60,
  destaque = c(FALSE, TRUE)
)

kpi$fec_mes_var <- (kpi$fec_mes_ref / kpi$fec_medio_historico_mes - 1) * 100
kpi$dec_mes_var <- (kpi$dec_mes_ref / kpi$dec_medio_historico_mes - 1) * 100

# FEC/DEC do mês de referência vs. mesmo mês do ANO ANTERIOR (não a média
# histórica) - segunda comparação pedida por Marco pra manchete (10/09/2026):
# "tem que falar da tendência vis a vis o ano anterior e com a série
# histórica" - as duas ficam lado a lado no texto, nunca misturadas.
mes_ano_passado_dfec_row <- dec_fec_sp |> filter(NumAno == ano_ref - 1, mes_inicio == mes_ref)
kpi$fec_var_anopassado <- if (nrow(mes_ano_passado_dfec_row) == 1) variacao_pct(kpi$fec_mes_ref, mes_ano_passado_dfec_row$FEC) else NA_real_
kpi$dec_var_anopassado <- if (nrow(mes_ano_passado_dfec_row) == 1) variacao_pct(kpi$dec_mes_ref, mes_ano_passado_dfec_row$DEC) else NA_real_

# Recorte só do mês de referência, usado no ranking/causas/mapa ====
base_mes <- base |> filter(NumAno == ano_ref, mes_inicio == mes_ref)

# Causa principal do aumento do mês - spec fechada com Marco em 10/09/2026
# (sessão de "vamos repensar", depois de descartar duas versões anteriores
# erradas). Regras da spec:
# 1) Compara SÓ o mês de referência contra o MESMO MÊS do ano anterior
#    (nunca acumulado, nunca outro mês) - reproduzível pra qualquer mês.
# 2) Usa a MESMA base filtrada do FEC/DEC (total >= 180s & IdeMotivoInterrupcao
#    == 0), não a base geral - achado importante: usar a base geral dá uma
#    causa principal DIFERENTE (a classificação de expurgo/emergência varia
#    de ano pra ano de forma desigual entre causas - ex. jul/2025 teve 48,5%
#    do impacto de árvore/vento "perdoado" como emergência ISE, jul/2026
#    quase nada - isso por si só muda o ranking de causa se a base não for
#    consistente com a métrica citada no texto). Ver LOG.md, sessão de
#    10/09/2026, pra o caso completo que motivou essa decisão.
# 3) % de cada causa é sobre o DELTA LÍQUIDO TOTAL (soma de todas as causas,
#    positivas e negativas) - não sobre a soma só das causas que cresceram
#    (evita % > 100% quando há causas caindo compensando as que sobem).
# 4) Nº de causas citadas na manchete é decisão editorial mês a mês (não
#    100% automática) - o código expõe as duas maiores prontas pra uso;
#    o texto decide quantas citar (uma quando a 2ª for pouco relevante,
#    duas quando ambas forem substanciais, como em julho/2026).
base_ff <- base |> filter(total >= 180, IdeMotivoInterrupcao == 0)

causa_aumento_mes <- base_ff |>
  filter(NumAno %in% c(ano_ref, ano_ref - 1), mes_inicio == mes_ref) |>
  mutate(causa_label = mapear_causa_final(causa_03, causa_04),
         ano_tipo = ifelse(NumAno == ano_ref, "atual", "passado")) |>
  group_by(ano_tipo, causa_label) |>
  summarise(UC = sum(NumUnidadeConsumidora), .groups = "drop") |>
  tidyr::pivot_wider(names_from = ano_tipo, values_from = UC, values_fill = 0) |>
  mutate(delta = atual - passado) |>
  arrange(desc(delta))

delta_liquido_total_causas <- sum(causa_aumento_mes$delta)
causa_aumento_mes <- causa_aumento_mes |>
  mutate(pct_do_aumento = delta / delta_liquido_total_causas * 100)

kpi$causa1_nome <- causa_aumento_mes$causa_label[1]
kpi$causa1_pct  <- causa_aumento_mes$pct_do_aumento[1]
kpi$causa2_nome <- causa_aumento_mes$causa_label[2]
kpi$causa2_pct  <- causa_aumento_mes$pct_do_aumento[2]

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
kpi$maior_evento_conjunto <- titulo_pt(maior_evento_row$DscConjuntoUnidadeConsumidora)

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
      Distrito = titulo_pt(nome_distrito),
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
