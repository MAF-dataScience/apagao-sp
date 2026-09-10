# Verifica se a série temporal mostrada no site (index.qmd, seção "Como
# [mês] se compara à série histórica", abas "Total" e "Por causa") bate com
# a base processada. Duas camadas de checagem, independentes entre si:
#
#   (1) reagregação da série feita do zero neste script - código
#       independente do site/R/dados.R, pra pegar bug de lógica que reler o
#       mesmo código não pegaria (contagem por mês, média móvel de 12m
#       recalculada por soma deslizante manual, não por stats::filter);
#   (2) o HTML de fato publicado (site/_site/index.html) - extrai o JSON
#       que os widgets plotly embutem na página e compara contra a base
#       atual, ou seja, checa o que o leitor realmente vê, não só o objeto
#       R em memória (pode ter ficado desatualizado se alguém esqueceu de
#       rodar `quarto render` depois de atualizar a base).
#
# Não é um script de pipeline (não gera nenhuma base nova) - é uma
# checagem de QA, pra rodar depois de: (a) atualizar a base processada,
# ou (b) rodar `quarto render` no site, antes de publicar.
#
# Script não editado pra rodar sozinho ainda - ver nota de ambiente no
# CLAUDE.md ("Ambiente técnico"): rodar via PowerShell nativo ou RStudio,
# nunca via Rscript.exe chamado pelo bridge Bash/MSYS (readRDS trava).

suppressPackageStartupMessages({
  library(dplyr)
  library(here)
  library(lubridate)
  library(jsonlite)
  library(stringr)
})

problemas <- character(0)
avisar <- function(msg) {
  problemas <<- c(problemas, msg)
  message("[FALHA] ", msg)
}
ok <- function(msg) message("[OK] ", msg)

## 1. Reagregação independente a partir da base bruta ========================

base <- readRDS(here("bases", "interrupcoes-energia-sampa-2018-2026.rds"))

# média móvel de 12 meses por soma deslizante manual - mecanismo diferente
# do stats::filter(..., sides = 1) usado em site/R/dados.R, de propósito
media_movel_manual <- function(n, janela = 12) {
  sapply(seq_along(n), function(i) {
    if (i < janela) return(NA_real_)
    mean(n[(i - janela + 1):i])
  })
}

serie_mensal_check <- base |>
  count(NumAno, mes_inicio, name = "n") |>
  mutate(data = as.Date(sprintf("%d-%02d-01", NumAno, mes_inicio))) |>
  arrange(data) |>
  mutate(media_movel_12m = media_movel_manual(n))

# aba "Por causa" do site usa causa_03 direto (MEIO AMBIENTE / PROPRIAS DO
# SISTEMA), não a taxonomia causa_04 reagrupada de mapear_causa_final()
# (essa é só do gráfico de barras de causas do mês/12m, seção diferente)
serie_causas_check <- base |>
  filter(causa_03 %in% c("MEIO AMBIENTE", "PROPRIAS DO SISTEMA")) |>
  count(NumAno, mes_inicio, causa_03, name = "n") |>
  mutate(
    data = as.Date(sprintf("%d-%02d-01", NumAno, mes_inicio)),
    causa_label = ifelse(causa_03 == "MEIO AMBIENTE", "Meio ambiente", "Próprias do sistema")
  ) |>
  arrange(data) |>
  group_by(causa_label) |>
  mutate(media_movel_12m = media_movel_manual(n)) |>
  ungroup()

## 2. Integridade da série (buracos, duplicatas, meses além do esperado) =====

meses_esperados <- seq(min(serie_mensal_check$data), max(serie_mensal_check$data), by = "month")
meses_faltando <- setdiff(meses_esperados, serie_mensal_check$data)
if (length(meses_faltando) > 0) {
  avisar(sprintf(
    "%d mes(es) faltando na serie mensal: %s",
    length(meses_faltando),
    paste(as.Date(meses_faltando, origin = "1970-01-01"), collapse = ", ")
  ))
} else {
  ok(sprintf(
    "serie mensal sem buracos (%s a %s, %d meses)",
    format(min(serie_mensal_check$data), "%m/%Y"),
    format(max(serie_mensal_check$data), "%m/%Y"),
    nrow(serie_mensal_check)
  ))
}

if (anyDuplicated(serie_mensal_check$data) > 0) {
  avisar("mes duplicado em serie_mensal_check (agregacao deveria dar 1 linha por ano-mes)")
} else {
  ok("nenhum mes duplicado na serie mensal")
}

# 2026 deve estar parcial (jan-jun, ver CLAUDE.md > "Defasagem de
# publicação") - avisa (não é erro) se a base já tiver meses além disso,
# só pra lembrar de atualizar este limite numa sessão futura
limite_2026 <- as.Date("2026-07-01")
meses_2026_alem_do_esperado <- serie_mensal_check |>
  filter(NumAno == 2026, data > limite_2026)
if (nrow(meses_2026_alem_do_esperado) > 0) {
  message(sprintf(
    "[INFO] base tem dado 2026 alem de %s (%s) - script desatualizado, nao e erro; atualizar limite_2026 no topo do script",
    format(limite_2026, "%m/%Y"),
    paste(format(meses_2026_alem_do_esperado$data, "%m/%Y"), collapse = ", ")
  ))
}

## 3. Compara contra o pipeline real do site (site/R/dados.R) ================

# site/R/dados.R usa here("..", "bases", ...) porque, quando o Quarto
# renderiza o site, o working directory fica em site/ (sentinela
# _quarto.yml) e here() resolve a raiz a partir dali. Mas here() cacheia a
# raiz detectada na PRIMEIRA chamada da sessão - como este script já
# chamou here() antes (pra ler a base, acima), só trocar o wd com
# setwd() não adianta, o cache continua apontando pra raiz do projeto.
# Solução: rodar site/R/dados.R numa sub-sessão nova do R (Rscript
# separado, mesma versão que está rodando este script), com o wd já
# correto desde o início - sem cache herdado, here() resolve certo do
# mesmo jeito que resolve quando o Quarto renderiza de verdade.
wrapper_path <- tempfile(fileext = ".R")
saida_path <- tempfile(fileext = ".rds")
writeLines(c(
  sprintf("setwd(%s)", deparse(as.character(here("site")))),
  "suppressPackageStartupMessages({library(dplyr); library(here); library(lubridate); library(sf)})",
  "env <- new.env()",
  'source("R/dados.R", local = env)',
  sprintf(
    "saveRDS(list(serie_mensal = env$serie_mensal, serie_causas = env$serie_causas), %s)",
    deparse(saida_path)
  )
), wrapper_path)

rscript_exe <- file.path(R.home("bin"), "Rscript.exe")
log_subprocesso <- system2(rscript_exe, args = shQuote(wrapper_path), stdout = TRUE, stderr = TRUE)
unlink(wrapper_path)

if (!file.exists(saida_path)) {
  avisar(sprintf(
    "nao consegui rodar site/R/dados.R numa sub-sessao pra comparar (ver saida abaixo) - pulando checagem 3:\n%s",
    paste(log_subprocesso, collapse = "\n")
  ))
  env_site <- list(serie_mensal = NULL, serie_causas = NULL)
} else {
  env_site <- readRDS(saida_path)
  unlink(saida_path)
}

if (is.null(env_site$serie_mensal)) {

  message("[INFO] checagem 3 (contra site/R/dados.R) pulada - ver motivo no aviso de falha acima")

} else {

# 3a. Total -----------------------------------------------------------------
comparar_total <- env_site$serie_mensal |>
  select(data, n_site = n, mm_site = media_movel_12m) |>
  full_join(serie_mensal_check |> select(data, n_check = n, mm_check = media_movel_12m), by = "data")

diff_n <- comparar_total |> filter(is.na(n_site) | is.na(n_check) | n_site != n_check)
if (nrow(diff_n) > 0) {
  avisar(sprintf(
    "%d mes(es) com contagem (n) diferente entre site/R/dados.R e a reagregacao independente:\n%s",
    nrow(diff_n), paste(capture.output(print(diff_n, n = Inf)), collapse = "\n")
  ))
} else {
  ok("contagem mensal (n) identica entre site/R/dados.R e a reagregacao independente")
}

diff_mm <- comparar_total |>
  filter(!is.na(mm_site) | !is.na(mm_check)) |>
  filter(is.na(mm_site) != is.na(mm_check) | abs(mm_site - mm_check) > 1e-6)
if (nrow(diff_mm) > 0) {
  avisar(sprintf(
    "%d mes(es) com media movel de 12m divergente (site vs. recalculo manual):\n%s",
    nrow(diff_mm), paste(capture.output(print(diff_mm, n = Inf)), collapse = "\n")
  ))
} else {
  ok("media movel de 12 meses (Total) identica entre site/R/dados.R e o recalculo manual")
}

# 3b. Por causa ---------------------------------------------------------------
comparar_causas <- env_site$serie_causas |>
  select(data, causa_label, n_site = n, mm_site = media_movel_12m) |>
  full_join(
    serie_causas_check |> select(data, causa_label, n_check = n, mm_check = media_movel_12m),
    by = c("data", "causa_label")
  )

diff_causas_n <- comparar_causas |> filter(is.na(n_site) | is.na(n_check) | n_site != n_check)
if (nrow(diff_causas_n) > 0) {
  avisar(sprintf(
    "%d linha(s) causa/mes com contagem divergente:\n%s",
    nrow(diff_causas_n), paste(capture.output(print(diff_causas_n, n = Inf)), collapse = "\n")
  ))
} else {
  ok("contagem mensal por causa (Meio ambiente / Proprias do sistema) identica entre site/R/dados.R e a reagregacao independente")
}

diff_causas_mm <- comparar_causas |>
  filter(!is.na(mm_site) | !is.na(mm_check)) |>
  filter(is.na(mm_site) != is.na(mm_check) | abs(mm_site - mm_check) > 1e-6)
if (nrow(diff_causas_mm) > 0) {
  avisar(sprintf(
    "%d linha(s) causa/mes com media movel de 12m divergente:\n%s",
    nrow(diff_causas_mm), paste(capture.output(print(diff_causas_mm, n = Inf)), collapse = "\n")
  ))
} else {
  ok("media movel de 12 meses por causa identica entre site/R/dados.R e o recalculo manual")
}

}

## 4. Compara contra o HTML de fato publicado (site/_site/index.html) ========

# extrai o JSON embutido de cada widget plotly e localiza os tracos pelo
# campo "name" (nao pela ordem de aparicao no HTML - mais robusto a
# mudanca de layout da pagina, ex. se uma aba nova for inserida antes)
html_path <- here("site", "_site", "index.html")

if (!file.exists(html_path)) {
  avisar(sprintf(
    "HTML renderizado nao encontrado em %s - rodar `quarto render` antes de checar contra o site publicado",
    html_path
  ))
} else {
  html_mtime <- file.info(html_path)$mtime
  base_mtime <- file.info(here("bases", "interrupcoes-energia-sampa-2018-2026.rds"))$mtime
  if (html_mtime < base_mtime) {
    avisar(sprintf(
      "site/_site/index.html (%s) e mais antigo que a base (%s) - renderizar de novo antes de confiar nesta checagem",
      html_mtime, base_mtime
    ))
  }

  html_txt <- paste(readLines(html_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  blocos <- str_match_all(
    html_txt,
    '(?s)<script type="application/json" data-for="htmlwidget-[a-f0-9]+">(.*?)</script>'
  )[[1]][, 2]

  # NA numerica (ex. media movel dos primeiros 11 meses) vira `null` no
  # JSON - fromJSON(simplifyVector = FALSE) devolve isso como elemento
  # NULL da lista, e um unlist() ingenuo descartaria o elemento em vez de
  # virar NA, desalinhando x (datas) e y (valores). Os helpers abaixo
  # preservam a posicao.
  vetor_num <- function(lst) vapply(lst, function(v) if (is.null(v)) NA_real_ else as.numeric(v), numeric(1))
  vetor_chr <- function(lst) vapply(lst, function(v) if (is.null(v)) NA_character_ else as.character(v), character(1))

  extrair_traco <- function(nome_traco) {
    for (bloco in blocos) {
      j <- tryCatch(fromJSON(bloco, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(j)) next
      tracos <- j$x$data
      if (is.null(tracos)) next
      for (tr in tracos) {
        if (!is.null(tr$name) && identical(tr$name, nome_traco)) {
          return(data.frame(
            data = as.Date(vetor_chr(tr$x)),
            y = vetor_num(tr$y)
          ))
        }
      }
    }
    NULL
  }

  comparar_traco_html <- function(traco_check, coluna_check, nome_traco, tolerancia = 0) {
    html_df <- extrair_traco(nome_traco)
    if (is.null(html_df)) {
      avisar(sprintf("nao encontrei o traco '%s' no HTML publicado (nome mudou no index.qmd? script desatualizado)", nome_traco))
      return(invisible())
    }
    comp <- traco_check |>
      select(data, valor_check = all_of(coluna_check)) |>
      full_join(html_df |> rename(valor_html = y), by = "data")
    diff <- comp |>
      filter(!is.na(valor_check) | !is.na(valor_html)) |>
      filter(is.na(valor_check) != is.na(valor_html) | abs(valor_check - valor_html) > tolerancia)
    if (nrow(diff) > 0) {
      avisar(sprintf(
        "%d mes(es) onde '%s' no HTML publicado diverge da base atual (tolerancia %.2f):\n%s",
        nrow(diff), nome_traco, tolerancia, paste(capture.output(print(diff, n = Inf)), collapse = "\n")
      ))
    } else {
      ok(sprintf("traco '%s' do HTML publicado bate com a base atual", nome_traco))
    }
  }

  comparar_traco_html(serie_mensal_check, "n", "Mensal")
  # tolerancia 0.5: o hovertemplate do grafico ja arredonda pra inteiro
  # (%{y:.0f}), mas o valor numerico do traco em si nao e arredondado -
  # tolerancia so de guarda contra ruido de ponto flutuante, nao pra
  # mascarar divergencia real
  comparar_traco_html(serie_mensal_check, "media_movel_12m", "Média móvel (12 meses)", tolerancia = 0.5)

  comparar_traco_html(
    serie_causas_check |> filter(causa_label == "Meio ambiente"), "n", "Meio ambiente (mensal)"
  )
  comparar_traco_html(
    serie_causas_check |> filter(causa_label == "Próprias do sistema"), "n", "Próprias do sistema (mensal)"
  )
}

## 5. Resumo ===================================================================

cat("\n==============================\n")
if (length(problemas) == 0) {
  cat("TUDO OK - serie temporal do site bate com a base em todas as checagens.\n")
} else {
  cat(sprintf("%d PROBLEMA(S) ENCONTRADO(S):\n\n", length(problemas)))
  cat(paste0("- ", problemas, collapse = "\n\n"), "\n")
}
cat("==============================\n")
