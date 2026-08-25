# Apagão-SP

Observatório mensal de interrupções não programadas de energia elétrica na cidade de São Paulo, a partir dos microdados públicos da ANEEL. Iniciativa de divulgação de dados públicos da [MAF dataScience](https://github.com/MAF-dataScience/).

🔗 **Site publicado:** [maf-datascience.github.io/apagao-sp](https://maf-datascience.github.io/apagao-sp/)

## O que tem aqui

- `site/` — código-fonte do site (Quarto): `index.qmd` (edição do mês), `metodologia.qmd`, `edicoes.qmd`, `R/dados.R` (preparo de dados compartilhado).
- `scripts/` — pipeline completo em R, numerado pela ordem de execução (`01_` a `09_`), da conversão do dado bruto da ANEEL até os crosswalks geográficos usados no site.
- `bases/DICIONARIO_DADOS.md` — dicionário de colunas e notas de qualidade da base processada.
- `bases/METODOLOGIA_DEC_FEC.md` — metodologia completa do cálculo de DEC/FEC (Índice Apagão-SP), com validação contra a cartilha da ARSESP.

Os dados brutos e as bases processadas (arquivos `.rds`/`.csv` de saída dos scripts) não estão neste repositório — veja "Como reproduzir" abaixo.

## Fonte dos dados

- **Microdado de interrupções:** ANEEL — [Interrupções de Energia Elétrica nas Redes de Distribuição](https://dadosabertos.aneel.gov.br/dataset/interrupcoes-de-energia-eletrica-nas-redes-de-distribuicao) (dados abertos, atualização mensal declarada).
- **Geometria da rede** (conjuntos elétricos, alimentadores, pontos de conexão de UC): extrato público da BDGD (Base de Dados Geográfica da Distribuidora) da Enel-SP, disponível no [portal de dados abertos da ANEEL](https://dadosabertos.aneel.gov.br/).
- **Distritos oficiais de São Paulo:** shapefile do IBGE (malha municipal).
- **Índice Apagão-SP:** ancorado no DEC, indicador oficial de continuidade definido no [PRODIST Módulo 8](https://www2.aneel.gov.br/cedoc/aren2020888_prodist_modulo_8_v11.pdf) da ANEEL, validado contra a [cartilha de Continuidade no Fornecimento de Energia Elétrica da ARSESP](https://www.arsesp.sp.gov.br/Documentosgerais/Cartilha%20Tem%C3%A1tica_Continuidade%20Fornecimento.pdf).

## Como reproduzir

1. Baixe os microdados anuais de interrupção (2018 em diante) e o extrato BDGD da Enel-SP no portal de dados abertos da ANEEL (links acima).
2. Rode os scripts de `scripts/` na ordem numérica — cada um documenta no cabeçalho o que espera como entrada e o que gera como saída em `bases/`.
3. Rode `site/R/dados.R` (via `quarto render` dentro de `site/`) para montar as páginas a partir das bases geradas.

Ambiente: R (`tidyverse`, `sf`, `geobr`, `arrow`, `janitor`, `stringi`) + [Quarto](https://quarto.org).

## Metodologia e limitações

A leitura completa da metodologia — defasagem de publicação, filtros aplicados, taxonomia de causas, geografia estimada por distrito e limitações conhecidas — está na [página de Metodologia](https://maf-datascience.github.io/apagao-sp/metodologia.html) do site publicado.

## Licença

Código sob licença [MIT](LICENSE). Os dados originais são públicos, sob os termos de uso do [Portal de Dados Abertos da ANEEL](https://dadosabertos.aneel.gov.br/).

## Contato

[MAF dataScience](https://github.com/MAF-dataScience/) — mafdatascience@gmail.com
