
suppressMessages(source("R/dados.R"))
k <- kpi; print(str(k[sapply(k, function(x) length(x) == 1)]))
print(causa_aumento_mes)
d <- readRDS(here::here("..","bases", "dec_fec_mensal_sp.rds")); print(names(d))
for (m in 8:9) { cat("\n== mes", m, "\n"); print(d[d[[grep("mes", names(d), ignore.case=TRUE)[1]]] == m, ]) }
