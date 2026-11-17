/* DynamicsOps BCWMS - Servis Özeti (Business Central control add-in).
   Bağımlılık yok. Veri AL tarafındaki "DOPSWHS Service Summary Data" codeunit'inden JSON olarak gelir. */
(function () {
  'use strict';

  var TEXT = {
    tr: {
      title: 'Servis Özeti', print: 'Yazdır / PDF', copy: 'Metni kopyala', copied: 'Özet panoya kopyalandı.',
      copyFailed: 'Kopyalanamadı. Metni seçip elle kopyalayın.',
      loading: 'Özet hazırlanıyor…', nothing: 'Bu satış siparişi için açılmış servis kaydı yok.',
      basedOn: '{0} numaralı satış siparişine istinaden', noSalesOrder: 'Satış siparişi bağlanmamış',
      salesOrder: 'Satış siparişi', salesOpen: 'Açık sipariş', salesInvoiced: 'Faturalandı ({0})', salesUnknown: 'BC\'de bulunamadı',
      salesLines: 'Siparişteki ürünler', externalNo: 'Müşteri sipariş no', orderDate: 'Sipariş tarihi',
      customer: 'Müşteri', contact: 'İlgili', phone: 'Telefon', technician: 'Teknisyen', opened: 'Açılış', finished: 'Bitiş',
      serviceOrder: 'Servis siparişi', openOrder: 'Siparişi aç', priority: 'Öncelik',
      high: 'Yüksek', medium: 'Orta', low: 'Düşük',
      pending: 'Bekliyor', inprocess: 'Sahada', onhold: 'Beklemede', finishedSt: 'İş bitti · kayıt bekliyor', posted: 'Kaydedildi', closed: 'Kapandı',
      complaint: 'Bildirilen sorun', equipment: 'Servis yapılan ekipman', findings: 'Tespit ve yapılan işlem', serial: 'Seri no',
      where: 'Arıza yeri', what: 'Sorun', done: 'Yapılan işlem', worked: 'Çalışma',
      work: 'İşçilik ve kullanılan parçalar', labor: 'İşçilik', part: 'Parça', other: 'Diğer',
      colKind: 'Tür', colDesc: 'Açıklama', colQty: 'Miktar', totalLabor: 'Toplam işçilik', hours: 'saat',
      noWork: 'İşçilik veya parça girilmedi.',
      history: 'Servis geçmişi ve notlar', noHistory: 'Bu servis için kayıtlı not yok.',
      terminal: 'Terminal', office: 'BC', shipments: 'Servis sevkiyatı',
      generated: 'Hazırlanma', services: '{0} servis kaydı', notAssigned: 'Atanmadı',
      colNo: 'No'
    },
    en: {
      title: 'Service Summary', print: 'Print / PDF', copy: 'Copy as text', copied: 'Summary copied to the clipboard.',
      copyFailed: 'Could not copy. Select the text and copy it manually.',
      loading: 'Preparing the summary…', nothing: 'No service has been opened for this sales order.',
      basedOn: 'Based on sales order {0}', noSalesOrder: 'No sales order linked',
      salesOrder: 'Sales order', salesOpen: 'Open order', salesInvoiced: 'Invoiced ({0})', salesUnknown: 'Not found in BC',
      salesLines: 'Items on the order', externalNo: 'Customer order no.', orderDate: 'Order date',
      customer: 'Customer', contact: 'Contact', phone: 'Phone', technician: 'Technician', opened: 'Opened', finished: 'Finished',
      serviceOrder: 'Service order', openOrder: 'Open order', priority: 'Priority',
      high: 'High', medium: 'Medium', low: 'Low',
      pending: 'Pending', inprocess: 'On site', onhold: 'On hold', finishedSt: 'Work finished · awaiting posting', posted: 'Posted', closed: 'Closed',
      complaint: 'Reported problem', equipment: 'Serviced equipment', findings: 'Findings and work done', serial: 'Serial no.',
      where: 'Fault area', what: 'Problem', done: 'Work done', worked: 'Worked',
      work: 'Labor and parts used', labor: 'Labor', part: 'Part', other: 'Other',
      colKind: 'Type', colDesc: 'Description', colQty: 'Quantity', totalLabor: 'Total labor', hours: 'hours',
      noWork: 'No labor or parts entered.',
      history: 'Service history and notes', noHistory: 'No notes recorded for this service.',
      terminal: 'Terminal', office: 'BC', shipments: 'Service shipment',
      generated: 'Generated', services: '{0} service orders', notAssigned: 'Not assigned',
      colNo: 'No.'
    }
  };
  var STATUS_KEY = { pending: 'pending', inprocess: 'inprocess', onhold: 'onhold', finished: 'finishedSt', posted: 'posted', closed: 'closed' };
  // Steps of the job read as a timeline; typed texts read as notes.
  var NOTE_TYPES = { Note: 1, 'Fault Note': 1, 'Resolution Note': 1, 'Internal Note': 1, 'Order Description': 1, Created: 1 };

  var state = { locale: 'tr', data: null };
  var els = {};
  var toastTimer = null;

  function t(key) {
    var dict = TEXT[state.locale] || TEXT.en;
    return dict[key] != null ? dict[key] : (TEXT.en[key] != null ? TEXT.en[key] : key);
  }
  function fmt(text, value) { return String(text).replace('{0}', value); }
  function esc(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function invoke(name, args) {
    try { Microsoft.Dynamics.NAV.InvokeExtensibilityMethod(name, args || []); }
    catch (e) { if (window.console) { console.error('ServiceSummary', name, e); } }
  }
  function num(value) {
    var n = Number(value);
    if (!isFinite(n)) { return '0'; }
    var s = (Math.round(n * 100) / 100).toString();
    return state.locale === 'tr' ? s.replace('.', ',') : s;
  }
  function dateText(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
    if (!m) { return ''; }
    return state.locale === 'tr' ? m[3] + '.' + m[2] + '.' + m[1] : m[2] + '/' + m[3] + '/' + m[1];
  }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  // Log times are stored in UTC and shown in the reader's own time zone.
  function stampText(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) { return ''; }
    var day = state.locale === 'tr'
      ? pad(d.getDate()) + '.' + pad(d.getMonth() + 1) + '.' + d.getFullYear()
      : pad(d.getMonth() + 1) + '/' + pad(d.getDate()) + '/' + d.getFullYear();
    return day + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }
  function row(label, value) {
    if (!value) { return ''; }
    return '<div class="ss-kv"><span>' + esc(label) + '</span><b>' + esc(value) + '</b></div>';
  }

  // ---- render -------------------------------------------------------------
  function salesOrderHtml(so) {
    var stateText = so.state === 'open' ? t('salesOpen') : (so.state === 'invoiced' ? fmt(t('salesInvoiced'), so.invoiceNo || '') : t('salesUnknown'));
    var html = '<section class="ss-block ss-sales"><header class="ss-block-head"><h2>' + esc(t('salesOrder')) + ' ' + esc(so.no) + '</h2>' +
      '<span class="ss-pill st-' + esc(so.state) + '">' + esc(stateText) + '</span></header>';
    html += '<div class="ss-grid">' + row(t('customer'), so.customerName) + row(t('orderDate'), dateText(so.orderDate)) +
      row(t('externalNo'), so.externalDocumentNo || so.yourReference) + '</div>';
    var lines = so.lines || [];
    if (lines.length) {
      html += '<h3>' + esc(t('salesLines')) + '</h3><table class="ss-table"><thead><tr><th>' + esc(t('colNo')) + '</th><th>' + esc(t('colDesc')) +
        '</th><th class="num">' + esc(t('colQty')) + '</th></tr></thead><tbody>' +
        lines.map(function (l) {
          return '<tr><td class="code">' + esc(l.no) + '</td><td>' + esc(l.description) + '</td><td class="num">' + num(l.quantity) + ' ' + esc(l.unit) + '</td></tr>';
        }).join('') + '</tbody></table>';
    }
    return html + '</section>';
  }

  function itemHtml(item, order) {
    // Without a service item the line only repeats the reported problem shown just above.
    var named = item.serviceItemNo || (item.description && item.description !== order.description);
    var html = '<div class="ss-item">' + (named ? '<div class="ss-item-name">' + esc(item.description || item.serviceItemNo) + '</div>' : '');
    var sub = [item.serviceItemNo, item.serialNo ? t('serial') + ' ' + item.serialNo : ''].filter(Boolean).join(' · ');
    if (sub) { html += '<div class="ss-item-sub">' + esc(sub) + '</div>'; }
    var worked = '';
    if (item.startDate) {
      worked = dateText(item.startDate) + (item.startTime ? ' ' + item.startTime : '');
      if (item.finishDate) {
        worked += ' – ' + (item.finishDate === item.startDate ? '' : dateText(item.finishDate) + ' ') + (item.finishTime || '');
      }
    }
    var facts = row(t('where'), item.faultArea) + row(t('what'), item.symptom) + row(t('done'), item.resolution) + row(t('worked'), worked.trim());
    if (!named && !facts) { return ''; }
    if (facts) { html += '<div class="ss-grid">' + facts + '</div>'; }
    return html + '</div>';
  }

  function workHtml(lines) {
    if (!lines.length) { return '<p class="ss-muted">' + esc(t('noWork')) + '</p>'; }
    var labor = 0;
    var body = lines.map(function (l) {
      if (l.kind === 'labor') { labor += Number(l.quantity) || 0; }
      return '<tr><td><span class="ss-kind k-' + esc(l.kind) + '">' + esc(t(l.kind)) + '</span></td><td>' + esc(l.description) +
        (l.kind === 'part' && l.no ? ' <span class="code">' + esc(l.no) + '</span>' : '') + '</td><td class="num">' + num(l.quantity) + ' ' + esc(l.unit) + '</td></tr>';
    }).join('');
    var foot = labor > 0 ? '<tfoot><tr><td colspan="2">' + esc(t('totalLabor')) + '</td><td class="num">' + num(labor) + ' ' + esc(t('hours')) + '</td></tr></tfoot>' : '';
    return '<table class="ss-table"><thead><tr><th>' + esc(t('colKind')) + '</th><th>' + esc(t('colDesc')) + '</th><th class="num">' + esc(t('colQty')) +
      '</th></tr></thead><tbody>' + body + '</tbody>' + foot + '</table>';
  }

  function logHtml(log) {
    if (!log.length) { return '<p class="ss-muted">' + esc(t('noHistory')) + '</p>'; }
    return '<ol class="ss-log">' + log.map(function (e) {
      var isNote = !!NOTE_TYPES[e.type];
      return '<li class="' + (isNote ? 'is-note' : 'is-step') + '"><div class="ss-log-head"><b>' + esc(e.typeText) + '</b>' +
        '<span>' + esc(stampText(e.at)) + (e.who ? ' · ' + esc(e.who) : '') + '</span>' +
        '<span class="ss-src">' + esc(e.terminal ? t('terminal') : t('office')) + '</span></div>' +
        (e.text ? '<div class="ss-log-text">' + esc(e.text) + '</div>' : '') + '</li>';
    }).join('') + '</ol>';
  }

  function orderHtml(o) {
    var techs = (o.technicians || []).join(', ');
    var ships = (o.shipments || []).map(function (s) { return s.no + (s.date ? ' (' + dateText(s.date) + ')' : ''); }).join(', ');
    var html = '<section class="ss-block ss-order"><header class="ss-block-head"><h2>' + esc(t('serviceOrder')) + ' ' + esc(o.no) + '</h2>' +
      '<span class="ss-pill st-' + esc(o.status) + '">' + esc(t(STATUS_KEY[o.status] || o.status)) + '</span>' +
      (o.priority ? '<span class="ss-pill pr-' + esc(o.priority) + '">' + esc(t('priority')) + ': ' + esc(t(o.priority)) + '</span>' : '') +
      '<button type="button" class="ss-link no-print" data-action="open" data-no="' + esc(o.no) + '">' + esc(t('openOrder')) + ' ›</button></header>';
    html += '<div class="ss-grid">' + row(t('customer'), o.customerName) + row(t('contact'), o.contact) + row(t('phone'), o.phone) +
      row(t('technician'), techs || t('notAssigned')) + row(t('opened'), dateText(o.orderDate)) + row(t('finished'), dateText(o.finishingDate)) +
      row(t('shipments'), ships) + '</div>';
    if (o.description) { html += '<div class="ss-complaint"><span>' + esc(t('complaint')) + '</span><p>' + esc(o.description) + '</p></div>'; }
    var items = o.items || [];
    if (items.length) {
      var anyNamed = items.some(function (i) { return i.serviceItemNo || (i.description && i.description !== o.description); });
      var itemsHtml = items.map(function (i) { return itemHtml(i, o); }).join('');
      if (itemsHtml) { html += '<h3>' + esc(t(anyNamed ? 'equipment' : 'findings')) + '</h3>' + itemsHtml; }
    }
    html += '<h3>' + esc(t('work')) + '</h3>' + workHtml(o.lines || []);
    html += '<h3>' + esc(t('history')) + '</h3>' + logHtml(o.log || []);
    return html + '</section>';
  }

  function render() {
    if (!els.root) { return; }
    // Turkish capitals (İ, I) in the upper-case headings need the language on the element.
    els.root.setAttribute('lang', state.locale);
    els.print.textContent = t('print');
    els.copy.textContent = t('copy');
    var d = state.data;
    if (!d) { els.doc.innerHTML = '<div class="ss-empty">' + esc(t('loading')) + '</div>'; return; }
    var orders = d.orders || [];
    var first = orders[0] || {};
    var sub = d.salesOrderNo ? fmt(t('basedOn'), d.salesOrderNo) : t('noSalesOrder');
    var html = '<header class="ss-head"><div><div class="ss-company">' + esc(d.company) + '</div><h1>' + esc(t('title')) + '</h1>' +
      '<div class="ss-sub' + (d.salesOrderNo ? '' : ' is-none') + '">' + esc(sub) + '</div></div>' +
      '<div class="ss-head-meta">' + (first.customerName ? '<b>' + esc(first.customerName) + '</b>' : '') +
      (orders.length > 1 ? '<span>' + esc(fmt(t('services'), orders.length)) + '</span>' : (first.no ? '<span>' + esc(first.no) + '</span>' : '')) +
      '<span>' + esc(t('generated')) + ': ' + esc(stampText(d.generatedAt)) + '</span></div></header>';
    if (d.salesOrder) { html += salesOrderHtml(d.salesOrder); }
    html += orders.length ? orders.map(orderHtml).join('') : '<div class="ss-empty">' + esc(t('nothing')) + '</div>';
    els.doc.innerHTML = html;
  }

  // ---- plain text (clipboard) ----------------------------------------------
  function plainText() {
    var d = state.data;
    if (!d) { return ''; }
    var out = [];
    out.push((d.company ? d.company + ' — ' : '') + t('title'));
    out.push(d.salesOrderNo ? fmt(t('basedOn'), d.salesOrderNo) : t('noSalesOrder'));
    var so = d.salesOrder;
    if (so && (so.lines || []).length) {
      out.push('');
      out.push(t('salesLines') + ':');
      so.lines.forEach(function (l) { out.push('  - ' + [l.no, l.description].filter(Boolean).join(' ') + ' · ' + num(l.quantity) + ' ' + (l.unit || '')); });
    }
    (d.orders || []).forEach(function (o) {
      out.push('');
      out.push(t('serviceOrder') + ' ' + o.no + ' — ' + t(STATUS_KEY[o.status] || o.status));
      if (o.customerName) { out.push(t('customer') + ': ' + o.customerName); }
      out.push(t('technician') + ': ' + ((o.technicians || []).join(', ') || t('notAssigned')));
      if (o.orderDate) { out.push(t('opened') + ': ' + dateText(o.orderDate) + (o.finishingDate ? ' · ' + t('finished') + ': ' + dateText(o.finishingDate) : '')); }
      if (o.description) { out.push(t('complaint') + ': ' + o.description); }
      (o.items || []).forEach(function (i) {
        out.push(t('equipment') + ': ' + [i.description, i.serviceItemNo].filter(Boolean).join(' · '));
        var facts = [i.faultArea ? t('where') + ': ' + i.faultArea : '', i.symptom ? t('what') + ': ' + i.symptom : '', i.resolution ? t('done') + ': ' + i.resolution : ''].filter(Boolean);
        if (facts.length) { out.push('  ' + facts.join(' · ')); }
      });
      var lines = o.lines || [];
      if (lines.length) {
        out.push(t('work') + ':');
        lines.forEach(function (l) { out.push('  - ' + t(l.kind) + ': ' + l.description + ' · ' + num(l.quantity) + ' ' + (l.unit || '')); });
      }
      var log = o.log || [];
      if (log.length) {
        out.push(t('history') + ':');
        log.forEach(function (e) { out.push('  - ' + stampText(e.at) + ' ' + (e.who ? e.who + ' · ' : '') + e.typeText + (e.text ? ': ' + e.text : '')); });
      }
    });
    return out.join('\n');
  }
  function copyText() {
    var text = plainText();
    function fallback() {
      var area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      document.body.removeChild(area);
      toast(ok ? t('copied') : t('copyFailed'), !ok);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { toast(t('copied'), false); }, fallback);
    } else { fallback(); }
  }
  // Printing a frame inside the Business Central page is unreliable across browsers, so the
  // summary is printed from a window of its own that holds nothing but the document.
  function printSummary() {
    // The add-in's own stylesheets are linked again by URL, so the copy looks exactly like the page.
    var styles = '';
    var nodes = document.querySelectorAll('link[rel="stylesheet"], style');
    for (var i = 0; i < nodes.length; i++) {
      styles += nodes[i].tagName === 'LINK' ? '<link rel="stylesheet" href="' + esc(nodes[i].href) + '">' : '<style>' + nodes[i].textContent + '</style>';
    }
    var win = null;
    try { win = window.open('', '_blank'); } catch (e) { win = null; }
    if (!win) { window.focus(); window.print(); return; }
    var title = t('title') + (state.data && (state.data.serviceOrderNo || state.data.salesOrderNo) ? ' ' + (state.data.serviceOrderNo || state.data.salesOrderNo) : '');
    var copy = els.doc.cloneNode(true);
    var hidden = copy.querySelectorAll('.no-print');
    for (var k = 0; k < hidden.length; k++) { hidden[k].parentNode.removeChild(hidden[k]); }
    var printed = false;
    function go() { if (printed) { return; } printed = true; win.focus(); win.print(); }
    win.document.open();
    win.document.write('<!DOCTYPE html><html lang="' + state.locale + '"><head><meta charset="utf-8"><title>' + esc(title) + '</title>' + styles +
      '<style>html,body{height:auto;background:#fff}.ss{height:auto;display:block;padding:24px}.ss-doc{border:0;box-shadow:none;padding:0}</style></head>' +
      '<body><div class="ss"><article class="ss-doc">' + copy.innerHTML + '</article></div></body></html>');
    win.document.close();
    // Print once the stylesheets are in; the timer covers browsers that do not fire load here.
    try { win.addEventListener('load', go); } catch (e) { /* fall through to the timer */ }
    setTimeout(go, 1500);
  }

  function toast(text, isError) {
    els.toast.textContent = text;
    els.toast.className = 'ss-toast is-open' + (isError ? ' is-error' : '');
    if (toastTimer) { clearTimeout(toastTimer); }
    toastTimer = setTimeout(function () { els.toast.className = 'ss-toast'; }, isError ? 7000 : 3000);
  }

  function onClick(ev) {
    var el = ev.target.closest ? ev.target.closest('[data-action]') : null;
    if (!el) { return; }
    switch (el.getAttribute('data-action')) {
      case 'print': printSummary(); break;
      case 'copy': copyText(); break;
      case 'open': invoke('OpenOrder', [el.getAttribute('data-no')]); break;
    }
  }

  function init() {
    if (els.root) { return; }
    var host = document.getElementById('controlAddIn') || document.body;
    host.innerHTML =
      '<div class="ss">' +
      '<div class="ss-bar no-print"><button type="button" class="ss-btn primary" data-action="print"></button>' +
      '<button type="button" class="ss-btn" data-action="copy"></button></div>' +
      '<div class="ss-scroll"><article class="ss-doc"></article></div>' +
      '<div class="ss-toast no-print" role="status" aria-live="polite"></div>' +
      '</div>';
    els.root = host.querySelector('.ss');
    els.doc = host.querySelector('.ss-doc');
    els.print = host.querySelector('[data-action="print"]');
    els.copy = host.querySelector('[data-action="copy"]');
    els.toast = host.querySelector('.ss-toast');
    els.root.addEventListener('click', onClick);
    render();
  }

  // ---- AL procedures -------------------------------------------------------
  window.SetLocale = function (code) {
    var c = String(code || '');
    state.locale = (c.replace(/\D/g, '') === '1055' || /^tr/i.test(c)) ? 'tr' : 'en';
    render();
  };
  window.SetData = function (json) {
    try { state.data = JSON.parse(json); } catch (e) { state.data = { orders: [] }; }
    render();
  };
  window.DOPSWHSServiceSummary = { init: init };
})();
