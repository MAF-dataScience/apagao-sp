// Faixa "última atualização da ANEEL" da edição do mês.
// Lê aneel_status.json, que o monitor diário (scripts/00_monitor_aneel.ps1) publica na
// gh-pages a cada mudança na ANEEL, e calcula "há N dias" no navegador de quem abre a
// página, então o contador nunca fica parado. Se o JSON falhar, fica o texto do render.
(function () {
  var el = document.querySelector('.status-aneel');
  if (!el) return;
  // edição arquivada é retrato do que circulou na época: não mostrar status ao vivo
  if (document.title.indexOf('[Edição arquivada') === 0) return;

  var TZ = 'America/Sao_Paulo';
  function diaSP(d) { return d.toLocaleDateString('en-CA', { timeZone: TZ }); } // AAAA-MM-DD
  function dataBR(iso) { return new Date(iso).toLocaleDateString('pt-BR', { timeZone: TZ }); }
  function diasEntre(isoA, isoB) {
    return Math.round((Date.parse(diaSP(new Date(isoB))) - Date.parse(diaSP(new Date(isoA)))) / 86400000);
  }

  fetch('aneel_status.json', { cache: 'no-store' })
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (s) {
      var n = diasEntre(s.ultima_publicacao, new Date().toISOString());
      var ha = n <= 0 ? 'hoje' : (n === 1 ? 'há 1 dia' : 'há ' + n + ' dias');
      var txt = 'Última atualização da base pela ANEEL: ' + dataBR(s.ultima_publicacao) + ' (' + ha + ').';

      // intervalo típico entre publicações, só quando o histórico já é longo o bastante
      var datas = (s.historico || []).map(function (h) { return h.data; }).sort();
      if (datas.length >= 4) {
        var intervalos = [];
        for (var i = 1; i < datas.length; i++) intervalos.push(diasEntre(datas[i - 1], datas[i]));
        intervalos.sort(function (a, b) { return a - b; });
        var m = intervalos.length;
        var mediana = m % 2 ? intervalos[(m - 1) / 2] : Math.round((intervalos[m / 2 - 1] + intervalos[m / 2]) / 2);
        txt += ' Intervalo típico entre atualizações: ' + mediana + ' dias.';
      }

      var extratoEdicao = el.getAttribute('data-extrato-edicao');
      if (extratoEdicao && s.ultima_publicacao_ano_corrente > extratoEdicao) {
        txt += ' A ANEEL atualizou a base depois do fechamento desta edição. A próxima já está em preparação.';
      } else {
        txt += ' Dados disponíveis até ' + el.getAttribute('data-mes-ref') + '.';
      }
      el.querySelector('.status-aneel-texto').textContent = txt;
    })
    .catch(function () { /* mantém o texto gerado no render */ });
})();
