# APAGAO SP - Relatório mensal de 
# Marco Antonio Faganello - marcofaga@gmail.com - http://github.com/marcofaga
# Data de início: 11 de novembro de 2024
# Codificação: Banco em ASCII e Script em UTF-8
# Descrição do Script: Base, analise e gráficos

# AREA DO A4 na ABNT (com 5 cm de margens):
# Full page: 160x247mm em in 6.3x9.7 em px com 300 dpi 1890x2917
# Meia Página: 160X124mm / 6.3x4.9in / 1890x1470 (300 dpi)
# Áurea menor: 160x094mm / 6.3x3.7in / 1890x1110 (300 dpi)
# Áurea maior: 160X153mm / 6.3x6.0in / 1890X1800 (300 dpi)

# colorBrewer Divergente (4 cores): #e66101, #fdb863, #b2abd2, #5e3c99
# colorBrewer Sequencial (4 cores): #fef0d9, #fdcc8a, #fc8d59, #d7301f

# libraries ====================================================================

library(tidyverse)
library(beepr)
library(janitor)
library(sf)
library(stringi)
library(geobr)
library(here)
library(arrow)


# options=======================================================================
options(stringsAsFactors = F)
options(knitr.kable.NA = '-')
options(timeout=10000)

# functions=====================================================================
#apl <- list.files("../../../../R/functions/", full.names = T)
#lapply(apl, source)
#remove(apl)

# bd00 - Rds das bases =========================================================

# Dados de interrupção de energia elétrica disponíveis em:

#https://dadosabertos.aneel.gov.br/dataset/interrupcoes-de-energia-eletrica-nas-redes-de-distribuicao

#ap <- read_csv2(file.path(here("raw","interrup_energia","raw"), "interrupcoes-energia-eletrica-2026.csv"), locale = locale(encoding = "UTF-8")) # convertido em 23/08/2026, ver scripts/01_converter_2025_2026.R
#saveRDS(ap, here("raw","interrup_energia","interrupcoes-energia-eletrica-2026.rds"))
#ap <- read_csv2(file.path(here("raw","interrup_energia","raw"), "interrupcoes-energia-eletrica-2025.csv"), locale = locale(encoding = "UTF-8")) # convertido em 23/08/2026, ver scripts/01_converter_2025_2026.R
#saveRDS(ap, here("raw","interrup_energia","interrupcoes-energia-eletrica-2025.rds"))
#ap <- read_csv2(file.path(here("raw","interrup_energia","raw"), "interrupcoes-energia-eletrica-2024.csv"), locale = locale(encoding = "latin1")) # dados até 10 de novembro de 2024 apenas ATUALIZAR
#saveRDS(ap, here("raw","interrup_energia","interrupcoes-energia-eletrica-2024.rds"))
#ap <- read_csv2(file.path(here("raw","interrup_energia","raw"), "interrupcoes-energia-eletrica-2023.csv"), locale = locale(encoding = "latin1"))
#saveRDS(ap, here("raw","interrup_energia","interrupcoes-energia-eletrica-2023.rds"))
#ap <- read_csv2(file.path(here("raw","interrup_energia","raw"), "interrupcoes-energia-eletrica-2022.csv"), locale = locale(encoding = "latin1"))
#saveRDS(ap, here("raw","interrup_energia","interrupcoes-energia-eletrica-2022.rds"))
#ap <- read_csv2(file.path(here("raw","interrup_energia","raw"), "interrupcoes-energia-eletrica-2021.csv"), locale = locale(encoding = "latin1"))
#saveRDS(ap, here("raw","interrup_energia","interrupcoes-energia-eletrica-2021.rds"))
#ap <- read_csv2(file.path(here("raw","interrup_energia","raw"), "interrupcoes-energia-eletrica-2020.csv"), locale = locale(encoding = "latin1"))
#saveRDS(ap, here("raw","interrup_energia","interrupcoes-energia-eletrica-2020.rds"))
#ap <- read_csv2(file.path(here("raw","interrup_energia","raw"), "interrupcoes-energia-eletrica-2019.csv"), locale = locale(encoding = "latin1"))
#saveRDS(ap, here("raw","interrup_energia","interrupcoes-energia-eletrica-2019.rds"))
#ap <- read_csv2(file.path(here("raw","interrup_energia","raw"), "interrupcoes-energia-eletrica-2018.csv"), locale = locale(encoding = "latin1"))
#saveRDS(ap, here("raw","interrup_energia","interrupcoes-energia-eletrica-2018.rds"))

# NOTA (23/08/2026): 2017 foi descartado da série — a Eletropaulo/SP não está
# presente no arquivo bruto de 2017 da ANEEL sob nenhuma forma (nome, CNPJ ou
# geografia testados e descartados). Ver CLAUDE.md, seção "Lacuna de dados".
# A série deste projeto começa em 2018.


# bd01_interr_sp ===============================================================

# Segmentando os dados da capital ===========

camadas <- st_layers(here("raw", "interrup_energia", "ENEL_SP_390_2022-12-31_V11_20231001-2204.gdb.zip"))
conjuntos <- read_sf(here("raw", "interrup_energia", "ENEL_SP_390_2022-12-31_V11_20231001-2204.gdb.zip"), layer="CONJ")

# Leitura via parquet (24/08/2026, ver CLAUDE.md "Fonte dos dados") em vez de
# readRDS() do RDS nacional — o raw nacional é 5-10M linhas/ano, mas só
# ~250-470k (Eletropaulo) interessam pra esse projeto. Filtrar por agente já no
# open_dataset() (pushdown via arrow, antes de materializar em R) evita
# carregar o Brasil inteiro pra descartar 95% logo em seguida — mesmo
# resultado que o pipeline antigo (a filtragem por agente já era implícita:
# o filtro geográfico por conjunto, mais abaixo, só sobra linha Eletropaulo).
parquet_dir <- here("raw", "interrup_energia", "parquet")

ler_ano_schema_antigo <- function(ano) {
  open_dataset(file.path(parquet_dir, paste0("interrupcoes-energia-eletrica-", ano, ".parquet"))) |>
    filter(grepl("ELETROPAULO", toupper(NomAgenteRegulado))) |>
    collect()
}

# Anos com IdeConjuntoUnidadeConsumidora nativo no schema
interr25 <- ler_ano_schema_antigo(2025)
interr24 <- ler_ano_schema_antigo(2024)
interr19 <- ler_ano_schema_antigo(2019)
interr18 <- ler_ano_schema_antigo(2018)

# Anos SEM IdeConjuntoUnidadeConsumidora nativo (2020-2023) — recuperado via
# crosswalk nome->id construído a partir do shapefile CONJ.
# Ver scripts/02_crosswalk_conjuntos.R e CLAUDE.md, seção "Lacuna de dados"
# (94,4% de match; 8 conjuntos ficam sem ID e são descartados no filtro geográfico
# abaixo — a maioria parece mesmo ficar fora do município de SP).
xwalk <- readRDS(here("bases", "crosswalk_conjuntos_sp.rds"))

recuperar_id_via_crosswalk <- function(ano) {
  d <- ler_ano_schema_antigo(ano)
  d$NomAgenteRegulado <- trimws(d$NomAgenteRegulado)
  d$nome_norm <- stri_trans_general(toupper(trimws(d$DscConjuntoUnidadeConsumidora)), "Latin-ASCII")
  d <- d |> left_join(xwalk, by = "nome_norm")
  d$IdeConjuntoUnidadeConsumidora <- d$cod_id
  d$cod_id <- NULL
  d$nome_norm <- NULL
  d
}

interr23 <- recuperar_id_via_crosswalk(2023)
interr22 <- recuperar_id_via_crosswalk(2022)
interr21 <- recuperar_id_via_crosswalk(2021)
interr20 <- recuperar_id_via_crosswalk(2020)

# 2026 — schema novo da ANEEL (achado de 23/08/2026, ver CLAUDE.md "Lacuna de
# dados"): 26 colunas, nomenclatura trocada, causa já vem separada em 4 campos
# (Origem/Tipo/Causa/Detalhe) em vez de um único campo ";"-separado. Já tem
# CodConjUnidadeConsumidora nativo (não precisa do crosswalk de nome) — mesmo
# ID space do shapefile CONJ, confirmado por match direto (97 de 99 conjuntos
# de SP batem). Harmonizado pro formato antigo pra reaproveitar o resto do
# pipeline sem duplicar lógica de filtro/causa.
harmonizar_2026 <- function() {
  d <- open_dataset(file.path(parquet_dir, "interrupcoes-energia-eletrica-2026.parquet")) |>
    filter(NomAgente == "ELETROPAULO METROPOLITANA ELETRICIDADE DE SAO PAULO S.A.") |>
    collect()
  # DscMotivoExpurgo (schema 2026) -> IdeMotivoInterrupcao (mesmos códigos 0-8
  # do campo IdeMotivoExpurgo do dicionário oficial da ANEEL, ver
  # bases/DICIONARIO_DADOS.md e CLAUDE.md, "Índice Apagão-SP (DEC/FEC)").
  # Achado de 23/08/2026: harmonizar_2026() original deixava esse campo NA
  # pra todo 2026 — bloqueava o filtro de expurgo do DEC/FEC pra esse ano.
  #
  # DscAlimentadorSubestacao/DscSubestacaoDistribuicao (achado de 24/08/2026,
  # ver LOG.md — investigação de duplicação): o schema 2026 não tem essas
  # colunas como texto descritivo, só como código (CodAlimentador/CodSubestacao)
  # — harmonização original deixava ambas NA. Isso mascarava sub-eventos
  # legítimos como se fossem duplicata: uma mesma ocorrência pode gerar 2+
  # linhas legítimas quando atinge mais de um alimentador dentro do mesmo
  # conjunto (mesmo início/fim/causa, alimentador diferente) — confirmado
  # comparando com o padrão idêntico em 2018-2025, onde subestação/alimentador
  # já eram usados como parte da chave "de fato" do registro. Mapeado como
  # código (não descrição) — não é 100% equivalente ao texto de 2018-2025, mas
  # já resolve a ambiguidade de duplicação.
  mapa_expurgo <- c(
    "Não houve Expurgo" = 0,
    "Falha nas instalações da unidade consumidora sem afetar terceiros" = 1,
    "Obras de interesse exclusivo do usuário" = 2,
    "Interrupção em Situação de Emergência (ISE) por meio de CHI" = 3,
    "Interrupção em Situação de Emergência (ISE) por meio de decreto" = 3,
    "Suspensão por inadimplemento do consumidor" = 4,
    "Interrupção vinculada a programa de racionamento instituído pela União" = 5,
    "Interrupção ocorrida em Dia Crítico" = 6,
    "Interrupção oriunda de atuação de ERAC estabelecido pelo ONS" = 7,
    "Interrupção de origem externa ao sistema de distribuição" = 8
  )
  tibble(
    DatGeracaoConjuntoDados = d$DatGeracaoConjuntoDados,
    IdeConjuntoUnidadeConsumidora = d$CodConjUnidadeConsumidora,
    DscConjuntoUnidadeConsumidora = d$DscConjuntoUnidadeConsumidora,
    DscAlimentadorSubestacao = as.character(d$CodAlimentador),
    DscSubestacaoDistribuicao = as.character(d$CodSubestacao),
    NumOrdemInterrupcao = as.character(d$CodInterrupcao),
    DscTipoInterrupcao = NA_character_,
    IdeMotivoInterrupcao = unname(mapa_expurgo[d$DscMotivoExpurgo]),
    DatInicioInterrupcao = d$DatInicioInterrupcao,
    DatFimInterrupcao = d$DatFimInterrupcao,
    DscFatoGeradorInterrupcao = paste(d$DscFatoGeradorOrigem, d$DscFatoGeradorTipo, d$DscFatoGeradorCausa, d$DscFatoGeradorDetalhe, sep = " - "),
    NumNivelTensao = d$NumNivelTensao,
    NumUnidadeConsumidora = d$QtdConsumidoresAfetados,
    NumConsumidorConjunto = d$QtdConsumidoresAtivos,
    NumAno = d$AnoCompetencia,
    NomAgenteRegulado = d$NomAgente,
    SigAgente = d$SigAgente,
    NumCPFCNPJ = as.character(d$NumCNPJDistribuidora)
  )
}

interr26 <- harmonizar_2026()

interr <- bind_rows(interr26, interr25, interr24, interr23, interr22, interr21, interr20, interr19, interr18)
interr <- interr |> filter(!is.na(NumAno))

# Dedup de linhas 100% identicas (achado de 24/08/2026, investigacao de
# duplicacao — ver LOG.md e CLAUDE.md "Proximos passos"): 14 linhas
# duplicadas encontradas em 2020 (raw nacional, ja existiam assim antes do
# crosswalk — nao e efeito do join). Volume desprezivel (~0,0005% da serie
# inteira) mas sem motivo pra manter — rede de seguranca pra qualquer ano
# futuro que tenha o mesmo problema na fonte.
n_antes_dedup <- nrow(interr)
interr <- interr |> distinct()
cat("Dedup (linhas 100% identicas): removidas", n_antes_dedup - nrow(interr), "linhas\n")

apid <- unique(conjuntos$COD_ID)
interr$NomAgenteRegulado <- trimws(interr$NomAgenteRegulado)

# definindo os conjuntos que ficam em São Paulo
# NOTA (23/08/2026): geobr::read_municipality() está quebrado para SP nesta
# versão do pacote (1.9.1) — o host primário (ipea.gov.br) devolve 404 pro
# arquivo do estado 35, e o fallback pro mirror do GitHub tem um bug (checa a
# mesma URL quebrada duas vezes em vez de checar a URL de fallback), então
# nunca cai pro mirror que funciona. Baixando o mesmo .gpkg direto do mirror
# do GitHub (fonte oficial do pacote, só bypassando a lógica de fallback
# quebrada) e cacheando em raw/.
municipio_sp_path <- here("raw", "geobr", "municipio_sp_2022.gpkg")
if (!file.exists(municipio_sp_path)) {
  dir.create(dirname(municipio_sp_path), recursive = TRUE, showWarnings = FALSE)
  download.file(
    "https://github.com/ipeaGIT/geobr/releases/download/v1.7.0/35municipality_2022_simplified.gpkg",
    municipio_sp_path, mode = "wb"
  )
}
mapasp <- read_sf(municipio_sp_path) |> filter(code_muni == 3550308)
apw <- st_intersects(conjuntos, mapasp)
apw <- map(apw, ~ifelse(length(.) == 0, NA, .))
apw <- unlist(apw)
apw <- which(!is.na(apw))
conjuntos$sp <- NA
conjuntos$sp[apw] <- TRUE
apo <- conjuntos |> filter(sp)

# Calculando as áreas de intersecção. Vamos manter apenas as features
# que intersecicionam mais de 50%.
interseccao <- st_intersection(conjuntos, mapasp)
area_interseccao <- st_area(interseccao)
area2 <- st_area(apo)
aporc <- area_interseccao/area2
aporc <- as.numeric(aporc) > 0.5
apo$sp <- aporc
apo$sp[apo$NOME == "VARGINHA"] <- TRUE # INdlcusão do conjunto varginha para preencher o buraco que fica na zona sul
apo2 <- apo |> filter(sp)

interrsp <- interr |> filter(IdeConjuntoUnidadeConsumidora %in% apo2$COD_ID)
interrsp$NomAgenteRegulado  <- stri_trans_general(toupper(interrsp$NomAgenteRegulado), "Latin-ASCII")
# todos os de São Paulo tem como nome o agente ELETROPAULO METROPOLITANA ELETRICIDADE DE SAO PAULO S.A.
interrsp$inicio_ts <- as.numeric(interrsp$DatInicioInterrupcao, tz = "UTC")
interrsp$fim_ts <- as.numeric(interrsp$DatFimInterrupcao, tz = "UTC")

interrsp$total <- interrsp$fim_ts-interrsp$inicio_ts
interrsp$total_horas <- interrsp$total/3600

interrsp$mes_inicio <- month(interrsp$DatInicioInterrupcao)
interrsp$mes_fim <- month(interrsp$DatFimInterrupcao)

apdsc <- interrsp$DscFatoGeradorInterrupcao
apdsc <- stri_trans_general(toupper(apdsc), "Latin-ASCII")
apdsc <- gsub(" - ", ";", apdsc)
apdsc <- strsplit(apdsc, ";")
apdsc1 <- unlist(map(apdsc, ~.[1]))
apdsc2 <- unlist(map(apdsc, ~.[2]))
apdsc3 <- unlist(map(apdsc, ~.[3]))
apdsc4 <- unlist(map(apdsc, ~.[4]))

interrsp$causa_01 <- apdsc1
interrsp$causa_02 <- apdsc2
interrsp$causa_03 <- apdsc3
interrsp$causa_04 <- apdsc4

interrsp <- interrsp |> filter(causa_01 == "INTERNA")
interrsp <- interrsp |> filter(causa_03 != "NAO CLASSIFICADA")
interrsp <- interrsp |> filter(causa_02 == "NAO PROGRAMADA")
interrsp <- interrsp |> filter(causa_04 != "EMPRESAS DE SERVICOS PUBLICOS OU SUAS CONTRATADAS")
interrsp <- interrsp |> filter(causa_04 != "NAO IDENTIFICADA")
interrsp$prop_atingidas <- interrsp$NumUnidadeConsumidora/interrsp$NumConsumidorConjunto*100

saveRDS(interrsp, here("bases", "interrupcoes-energia-sampa-2018-2026.rds"))

# script =======================================================================

# A001 - Dados no mês ==========================================================

mes_ref <- 9
interrsp_mes <- interrsp |> filter(mes_inicio == mes_ref)

dado_numero_interrup <- nrow(interrsp_mes)
dado_unidades_consumidoras_atingidas <- sum(interrsp_mes$NumUnidadeConsumidora)
dado_media_unidades_consumidoras_atingidas <- mean(interrsp_mes$NumUnidadeConsumidora)
dado_prop_media_unidades_atingidas <- mean(interrsp$prop_atingidas)
dado_prop_media_horas <- mean(interrsp$total_horas)

# A002 - Interrupções por mês ==================================================

apsum <-
  interrsp |>
  group_by(mes_inicio, NumAno) |>
  summarise(n = n(), .groups = "drop") |>
  mutate(data = dmy(paste0("01-", mes_inicio, "-", NumAno)))

grafico_serie_mensal <-
  ggplot(data = apsum, aes(x = data, y = n)) +
  geom_line(color = "#e66101", linewidth = 0.8) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(
    title = "Interrupções não programadas de energia elétrica em São Paulo",
    subtitle = "Contagem mensal, 2018-2026",
    x = NULL, y = "Nº de interrupções"
  ) +
  theme_minimal()

grafico_serie_mensal

# save =========================================================================
beepr::beep()
