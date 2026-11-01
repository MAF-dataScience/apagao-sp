# Monitor diario da ANEEL: checa na API CKAN do portal de dados abertos se algum
# extrato anual de interrupcoes ganhou versao nova e avisa no celular via ntfy.
# Roda pelo Agendador de Tarefas do Windows (tarefa "ApagaoSP - Monitor ANEEL").
#
# Estado local (gitignored, em bases/):
#   monitor_aneel_estado.txt  - nome + last_modified de cada extrato anual na ultima checagem
#   monitor_aneel_falhas.txt  - contador de falhas seguidas (avisa so na 2a, pra nao alarmar por instabilidade)
#   ntfy_topic.txt            - topico do ntfy (fora do script porque o repo e publico)
#   aneel_status.json         - historico publico de publicacoes da ANEEL (copia mestre)
#   monitor_aneel_push_falhas.txt - contador de falhas seguidas de publicacao na gh-pages
# O aviso de dado novo sai uma vez so por mudanca. Na primeira execucao so grava o estado.
#
# Status publico no site (desde 01/11/2026): a cada mudanca na ANEEL o script
# acrescenta uma entrada em aneel_status.json e publica o arquivo na branch gh-pages
# (worktree em $ghpages), so esse arquivo, com commit "Monitor ANEEL: ...". O site
# le o JSON no navegador e mostra "ultima atualizacao da ANEEL em X, ha N dias".
# A sincronizacao roda em toda execucao (idempotente): se um push falhar, a proxima
# execucao tenta de novo. Se houver commit manual nao publicado na gh-pages, o push
# automatico fica suspenso (avisa no ntfy) pra nao publicar trabalho em andamento.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$bases   = Join-Path $PSScriptRoot '..\bases'
$estado  = Join-Path $bases 'monitor_aneel_estado.txt'
$falhas  = Join-Path $bases 'monitor_aneel_falhas.txt'
$statusJson  = Join-Path $bases 'aneel_status.json'
$pushFalhas  = Join-Path $bases 'monitor_aneel_push_falhas.txt'
$ghpages = 'G:\Meu Drive\MAFData\divulgacao\apagao-sp-gh-pages'
$utf8SemBom = New-Object Text.UTF8Encoding $false
$topico  = (Get-Content (Join-Path $bases 'ntfy_topic.txt') -TotalCount 1).Trim()
$api     = 'https://dadosabertos.aneel.gov.br/api/3/action/package_show?id=interrupcoes-de-energia-eletrica-nas-redes-de-distribuicao'
$dataset = 'https://dadosabertos.aneel.gov.br/dataset/interrupcoes-de-energia-eletrica-nas-redes-de-distribuicao'

function Enviar-Ntfy($titulo, $texto, $tags, $prioridade = 'default') {
  $headers = @{ Title = $titulo; Tags = $tags; Priority = $prioridade; Click = $dataset }
  $corpo = [Text.Encoding]::UTF8.GetBytes($texto)
  Invoke-RestMethod -Uri "https://ntfy.sh/$topico" -Method Post -Headers $headers -Body $corpo `
    -ContentType 'text/plain; charset=utf-8' | Out-Null
}

# last_modified da API vem em UTC sem fuso ("2026-09-04T14:21:27.999580") -> ISO com Z, em segundos
function Para-IsoUtc($lm) { $lm.Substring(0, 19) + 'Z' }

function Salvar-Status($obj) {
  $json = ConvertTo-Json -InputObject $obj -Depth 5
  [IO.File]::WriteAllText($statusJson, $json, $utf8SemBom)
}

# Atualiza o JSON publico. $mudancas = linhas "nome last_modified" que mudaram (vazio = nada novo).
function Atualizar-Status($recursos, $mudancas) {
  if (Test-Path $statusJson) {
    $s = [IO.File]::ReadAllText($statusJson) | ConvertFrom-Json
    $historico = @($s.historico)
  } else {
    # semente: agrupa a data atual de cada extrato por dia (a API so guarda a ultima versao)
    $historico = @($recursos | Group-Object { $_.data.Substring(0, 10) } | Sort-Object Name | ForEach-Object {
      [pscustomobject]@{
        data     = ($_.Group | ForEach-Object { $_.data } | Sort-Object | Select-Object -Last 1)
        extratos = @($_.Group | ForEach-Object { $_.ano } | Sort-Object)
      }
    })
  }
  if ($mudancas) {
    $mudou = @($recursos | Where-Object { $mudancas -contains $_.linha })
    $historico += [pscustomobject]@{
      data     = ($mudou | ForEach-Object { $_.data } | Sort-Object | Select-Object -Last 1)
      extratos = @($mudou | ForEach-Object { $_.ano } | Sort-Object)
    }
  }
  $anoCorrente = ($recursos | ForEach-Object { $_.ano } | Sort-Object | Select-Object -Last 1)
  Salvar-Status ([ordered]@{
    fonte                           = $dataset
    ultima_publicacao               = ($recursos | ForEach-Object { $_.data } | Sort-Object | Select-Object -Last 1)
    ano_corrente                    = $anoCorrente
    ultima_publicacao_ano_corrente  = ($recursos | Where-Object { $_.ano -eq $anoCorrente }).data
    historico                       = $historico
  })
}

function Git-Ok { if ($LASTEXITCODE -ne 0) { throw "git falhou: $args" } }

# Publica aneel_status.json na gh-pages se o publicado estiver diferente da copia mestre.
function Sincronizar-GhPages {
  if (-not (Test-Path (Join-Path $ghpages '.git'))) { throw "worktree gh-pages nao encontrado em $ghpages" }
  Push-Location $ghpages
  try {
    git fetch -q origin gh-pages; Git-Ok 'fetch'
    if ([int](git rev-list --count HEAD..origin/gh-pages) -gt 0) { git merge -q --ff-only origin/gh-pages; Git-Ok 'merge --ff-only' }
    $destino = Join-Path $ghpages 'aneel_status.json'
    $conteudo = [IO.File]::ReadAllText($statusJson)
    if (-not (Test-Path $destino) -or [IO.File]::ReadAllText($destino) -ne $conteudo) {
      [IO.File]::WriteAllText($destino, $conteudo, $utf8SemBom)
    }
    if (git status --porcelain -- aneel_status.json) {
      git add -- aneel_status.json; Git-Ok 'add'
      git commit -q -m 'Monitor ANEEL: atualiza status de publicacao' -- aneel_status.json; Git-Ok 'commit'
    }
    $pendentes = @(git log origin/gh-pages..HEAD --format=%s)
    if ($pendentes.Count -gt 0) {
      if ($pendentes | Where-Object { $_ -notlike 'Monitor ANEEL:*' }) {
        throw 'ha commit manual nao publicado na gh-pages; push automatico suspenso ate ele ser publicado'
      }
      git push -q origin gh-pages; Git-Ok 'push'
      Write-Output 'Status publicado na gh-pages'
    }
  } finally { Pop-Location }
}

try {
  $resp = Invoke-RestMethod -Uri $api -TimeoutSec 60
  # so os zips anuais (o .parquet do mesmo ano muda junto)
  $recursos = @($resp.result.resources |
    Where-Object { $_.name -match '^interrupcoes-energia-eletrica-(\d{4})$' } |
    ForEach-Object {
      [pscustomobject]@{
        ano   = $_.name.Substring($_.name.Length - 4)
        data  = (Para-IsoUtc $_.last_modified)
        linha = "$($_.name) $($_.last_modified)"
      }
    })
  $atual = $recursos | ForEach-Object { $_.linha } | Sort-Object
  if (-not $atual) { throw 'Resposta da API sem extratos anuais' }
} catch {
  $n = 1
  if (Test-Path $falhas) { $n = [int](Get-Content $falhas -TotalCount 1) + 1 }
  Set-Content $falhas $n
  if ($n -eq 2) {
    Enviar-Ntfy 'Apagao-SP: monitor ANEEL falhou' "Duas checagens seguidas sem conseguir consultar a API da ANEEL. Erro: $($_.Exception.Message)" 'warning'
  }
  throw
}
if (Test-Path $falhas) { Remove-Item $falhas }

$novos = @()
if (-not (Test-Path $estado)) {
  Set-Content $estado $atual
  Write-Output 'Primeira execucao: estado inicial gravado, sem aviso'
} else {
  $anterior = Get-Content $estado
  $novos = @($atual | Where-Object { $anterior -notcontains $_ })
  if ($novos.Count -eq 0) {
    Write-Output 'Sem mudanca'
  } else {
    $texto = "Extrato novo (last_modified UTC):`n" + ($novos -join "`n") + "`n`nHora de rodar a atualização mensal do Apagão-SP."
    Enviar-Ntfy 'Apagao-SP: ANEEL atualizou o dado' $texto 'zap' 'high'
    Set-Content $estado $atual
    Write-Output "Mudou: $($novos -join '; ')"
  }
}

# Status publico: so reescreve o JSON se mudou algo (ou se ainda nao existe); a
# sincronizacao com a gh-pages roda sempre, pra reenviar um push que falhou antes.
if ($novos.Count -gt 0 -or -not (Test-Path $statusJson)) { Atualizar-Status $recursos $novos }
try {
  Sincronizar-GhPages
  if (Test-Path $pushFalhas) { Remove-Item $pushFalhas }
} catch {
  $n = 1
  if (Test-Path $pushFalhas) { $n = [int](Get-Content $pushFalhas -TotalCount 1) + 1 }
  Set-Content $pushFalhas $n
  if ($n -eq 1) {
    Enviar-Ntfy 'Apagao-SP: status do site nao publicado' "O monitor nao conseguiu publicar aneel_status.json na gh-pages. Tenta de novo na proxima execucao. Erro: $($_.Exception.Message)" 'warning'
  }
  throw
}
