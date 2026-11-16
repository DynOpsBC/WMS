/* DynamicsOps BCWMS - Servis Yönetimi panosu (Business Central control add-in).
   Bağımlılık yok. Veri AL tarafındaki "DOPSWHS Service Board Data" codeunit'inden JSON olarak gelir. */
(function () {
  'use strict';

  var TEXT = {
    tr: {
      search: 'Müşteri, sipariş no veya açıklama ara',
      allTechs: 'Tüm teknisyenler',
      refresh: 'Yenile',
      kpiOpen: 'Açık iş', kpiUnassigned: 'Atanmamış', kpiLate: 'Geciken', kpiToday: 'Bugün yanıt',
      kpiToShip: 'Kayıt bekliyor', kpiToInvoice: 'Faturaya hazır',
      colUnassigned: 'Atanmamış', colAssigned: 'Atandı', colInProgress: 'Sahada', colOnHold: 'Beklemede', colDone: 'Tamamlandı',
      hintUnassigned: 'Teknisyen bekliyor', hintAssigned: 'İşe başlanacak', hintInProgress: 'Teknisyen çalışıyor',
      hintOnHold: 'Parça veya müşteri bekleniyor', hintDone: 'Kayıt ve fatura',
      empty: 'Bu sütunda iş yok',
      high: 'Yüksek', medium: 'Orta', low: 'Düşük',
      late: 'Gecikti', today: 'Bugün', response: 'Yanıt',
      notAssigned: 'Teknisyen atanmadı',
      assign: 'Teknisyen ata', addTech: 'Teknisyen ekle',
      toShip: 'Kayıt bekliyor', toInvoice: 'Faturaya hazır',
      technicians: 'Teknisyenler', jobs: 'açık iş', hoursToday: 'bugün', hourShort: 'sa',
      noTechs: 'Henüz teknisyen yok. İlgili > Servis Teknisyenleri sayfasından ekleyin.',
      dlgTitle: 'Teknisyen ata', serviceItem: 'Servis maddesi', technician: 'Teknisyen', date: 'Tarih', hours: 'Planlanan saat',
      cancel: 'Vazgeç', doAssign: 'Ata', assigning: 'Atanıyor…', assigned: 'Teknisyen atandı.', pickTech: 'Bir teknisyen seçin.',
      badHours: 'Planlanan saat sıfırdan büyük olmalı.', badDate: 'Tarih seçin.',
      truncated: 'En yeni {0} sipariş gösteriliyor.', clear: 'Filtreleri temizle',
      loading: 'Servis işleri yükleniyor…', moreItems: '+{0} servis maddesi', noAssignRight: 'Atama için Servis Teknisyenleri sayfasında "Servis Yöneticisi" işaretli olmalısınız.',
      busyTech: 'Bugün {0} sa planlı', freeTech: 'Bugün boş', noMatch: 'Filtreye uyan iş yok.',
      noReply: 'Business Central yanıt vermedi. Panoyu yenileyip atamayı kontrol edin.'
    },
    en: {
      search: 'Search customer, order no. or description',
      allTechs: 'All technicians',
      refresh: 'Refresh',
      kpiOpen: 'Open jobs', kpiUnassigned: 'Unassigned', kpiLate: 'Overdue', kpiToday: 'Due today',
      kpiToShip: 'Awaiting posting', kpiToInvoice: 'Ready to invoice',
      colUnassigned: 'Unassigned', colAssigned: 'Assigned', colInProgress: 'On site', colOnHold: 'On hold', colDone: 'Finished',
      hintUnassigned: 'Needs a technician', hintAssigned: 'Work not started', hintInProgress: 'Technician working',
      hintOnHold: 'Waiting for parts or customer', hintDone: 'Posting and invoicing',
      empty: 'No jobs in this column',
      high: 'High', medium: 'Medium', low: 'Low',
      late: 'Overdue', today: 'Today', response: 'Response',
      notAssigned: 'No technician yet',
      assign: 'Assign technician', addTech: 'Add technician',
      toShip: 'Awaiting posting', toInvoice: 'Ready to invoice',
      technicians: 'Technicians', jobs: 'open jobs', hoursToday: 'today', hourShort: 'h',
      noTechs: 'No technicians yet. Add them on Related > Service Technicians.',
      dlgTitle: 'Assign technician', serviceItem: 'Service item', technician: 'Technician', date: 'Date', hours: 'Planned hours',
      cancel: 'Cancel', doAssign: 'Assign', assigning: 'Assigning…', assigned: 'Technician assigned.', pickTech: 'Select a technician.',
      badHours: 'Planned hours must be greater than zero.', badDate: 'Select a date.',
      truncated: 'Showing the newest {0} orders.', clear: 'Clear filters',
      loading: 'Loading service jobs…', moreItems: '+{0} service items', noAssignRight: 'To assign jobs, mark yourself as "Dispatcher" on the Service Technicians page.',
      busyTech: '{0} h planned today', freeTech: 'Free today', noMatch: 'No jobs match the filter.',
      noReply: 'Business Central did not answer. Refresh the board and check the assignment.'
    }
  };

  var COLUMNS = [
    { key: 'unassigned', title: 'colUnassigned', hint: 'hintUnassigned', stages: ['unassigned'] },
    { key: 'assigned', title: 'colAssigned', hint: 'hintAssigned', stages: ['assigned'] },
    { key: 'inprogress', title: 'colInProgress', hint: 'hintInProgress', stages: ['inprogress'] },
    { key: 'onhold', title: 'colOnHold', hint: 'hintOnHold', stages: ['onhold'] },
    { key: 'done', title: 'colDone', hint: 'hintDone', stages: ['toship', 'toinvoice'] }
  ];
  var KPIS = [
    { key: 'open', label: 'kpiOpen' },
    { key: 'unassigned', label: 'kpiUnassigned' },
    { key: 'late', label: 'kpiLate', tone: 'bad' },
    { key: 'today', label: 'kpiToday', tone: 'warn' },
    { key: 'toship', label: 'kpiToShip', tone: 'warn' },
    { key: 'toinvoice', label: 'kpiToInvoice', tone: 'good' }
  ];
  var PRIORITY_RANK = { high: 0, medium: 1, low: 2 };
  var AVATAR_COLORS = ['#5b4bdb', '#0e7c86', '#2563eb', '#be185d', '#15803d', '#7c3aed', '#0369a1', '#9333ea'];

  var state = {
    locale: 'tr',
    data: null,
    q: '',
    tech: '',
    kpi: '',
    dialog: null,
    lastData: 0,
    refreshAt: 0
  };
  var assignTimer = null;
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
  function lower(value) {
    var s = String(value == null ? '' : value);
    try { return s.toLocaleLowerCase(state.locale === 'tr' ? 'tr-TR' : 'en-US'); } catch (e) { return s.toLowerCase(); }
  }
  function upper(value) {
    var s = String(value == null ? '' : value);
    try { return s.toLocaleUpperCase(state.locale === 'tr' ? 'tr-TR' : 'en-US'); } catch (e) { return s.toUpperCase(); }
  }
  function invoke(name, args) {
    try {
      Microsoft.Dynamics.NAV.InvokeExtensibilityMethod(name, args || []);
    } catch (e) {
      if (window.console) { console.error('ServiceBoard', name, e); }
    }
  }
  function num(value) {
    var n = Number(value);
    if (!isFinite(n)) { return '0'; }
    var s = (Math.round(n * 100) / 100).toString();
    return state.locale === 'tr' ? s.replace('.', ',') : s;
  }

  // ---- dates -------------------------------------------------------------
  function parts(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
    return m ? { y: m[1], m: m[2], d: m[3] } : null;
  }
  function shortDate(iso, today) {
    var p = parts(iso);
    if (!p) { return ''; }
    var tp = parts(today);
    var sameYear = tp && tp.y === p.y;
    if (state.locale === 'tr') { return p.d + '.' + p.m + (sameYear ? '' : '.' + p.y); }
    return p.m + '/' + p.d + (sameYear ? '' : '/' + p.y);
  }
  function whenText(order, today) {
    if (!order.responseDate) { return ''; }
    var day = order.responseDate === today ? t('today') : shortDate(order.responseDate, today);
    return day + (order.responseTime ? ' ' + order.responseTime : '');
  }

  // ---- data helpers -----------------------------------------------------
  function orders() { return (state.data && state.data.orders) || []; }
  function technicians() { return (state.data && state.data.technicians) || []; }
  function isDone(order) { return order.stage === 'toship' || order.stage === 'toinvoice'; }
  function isDueToday(order) { return !isDone(order) && order.responseDate && order.responseDate === state.data.today; }
  function techByUser(user) {
    var list = technicians();
    for (var i = 0; i < list.length; i++) { if (list[i].user === user) { return list[i]; } }
    return null;
  }
  function matchesKpi(order, key) {
    switch (key) {
      case 'open': return !isDone(order);
      case 'unassigned': return order.stage === 'unassigned';
      case 'late': return !!order.overdue;
      case 'today': return isDueToday(order);
      case 'toship': return order.stage === 'toship';
      case 'toinvoice': return order.stage === 'toinvoice';
      default: return true;
    }
  }
  function matchesSearch(order) {
    if (!state.q) { return true; }
    var hay = [order.no, order.customerNo, order.name, order.city, order.description]
      .concat(order.technicians || [])
      .concat((order.items || []).map(function (i) { return i.serviceItemNo + ' ' + i.description; }))
      .join(' ');
    return lower(hay).indexOf(lower(state.q)) >= 0;
  }
  function matchesTech(order) {
    if (!state.tech) { return true; }
    var tech = techByUser(state.tech);
    if (!tech) { return true; }
    return (order.resourceNos || []).indexOf(tech.resourceNo) >= 0;
  }
  function visibleOrders() {
    return orders().filter(function (o) {
      return matchesKpi(o, state.kpi) && matchesSearch(o) && matchesTech(o);
    });
  }
  function compareOrders(a, b) {
    if (a.stage !== b.stage) { return a.stage === 'toship' ? -1 : (b.stage === 'toship' ? 1 : 0); }
    if (!!a.overdue !== !!b.overdue) { return a.overdue ? -1 : 1; }
    var pa = PRIORITY_RANK[a.priority], pb = PRIORITY_RANK[b.priority];
    if (pa !== pb) { return pa - pb; }
    var ra = a.responseDate || '9999', rb = b.responseDate || '9999';
    if (ra !== rb) { return ra < rb ? -1 : 1; }
    return a.no < b.no ? 1 : (a.no > b.no ? -1 : 0);
  }
  function initials(name) {
    var words = String(name || '?').trim().split(/\s+/);
    var s = words[0] ? words[0].charAt(0) : '?';
    if (words.length > 1) { s += words[words.length - 1].charAt(0); }
    return upper(s);
  }
  function avatarColor(name) {
    var h = 0, s = String(name || '');
    for (var i = 0; i < s.length; i++) { h = (h * 31 + s.charCodeAt(i)) >>> 0; }
    return AVATAR_COLORS[h % AVATAR_COLORS.length];
  }
  function avatar(name, extraClass) {
    return '<span class="sb-avatar ' + (extraClass || '') + '" style="background:' + avatarColor(name) + '" title="' + esc(name) + '">' + esc(initials(name)) + '</span>';
  }

  // ---- rendering --------------------------------------------------------
  function render() {
    if (!els.root) { return; }
    if (!state.data) {
      els.main.innerHTML = '<div class="sb-loading"><span class="sb-spinner"></span>' + esc(t('loading')) + '</div>';
      return;
    }
    els.search.placeholder = t('search');
    renderKpis();
    renderTechs();
    renderBoard();
  }

  function renderKpis() {
    var all = orders();
    els.kpis.innerHTML = KPIS.map(function (k) {
      var count = all.filter(function (o) { return matchesKpi(o, k.key); }).length;
      var active = state.kpi === k.key;
      return '<button type="button" class="sb-kpi' + (k.tone ? ' tone-' + k.tone : '') + (active ? ' is-active' : '') +
        (count === 0 ? ' is-zero' : '') + '" data-action="kpi" data-key="' + k.key + '" aria-pressed="' + active + '">' +
        '<span class="sb-kpi-num">' + count + '</span><span class="sb-kpi-label">' + esc(t(k.label)) + '</span></button>';
    }).join('');
  }

  function renderTechs() {
    var list = technicians();
    if (!list.length) {
      els.techs.innerHTML = '<div class="sb-techs-empty">' + esc(t('noTechs')) + '</div>';
      return;
    }
    var maxJobs = 1;
    list.forEach(function (x) { if (x.activeJobs > maxJobs) { maxJobs = x.activeJobs; } });
    els.techs.innerHTML = '<span class="sb-techs-title">' + esc(t('technicians')) + '</span>' + list.map(function (x) {
      var active = state.tech === x.user;
      var load = Math.min(100, Math.round((x.activeJobs / maxJobs) * 100));
      return '<button type="button" class="sb-tech' + (active ? ' is-active' : '') + '" data-action="tech" data-user="' + esc(x.user) + '" aria-pressed="' + active + '">' +
        avatar(x.name) +
        '<span class="sb-tech-text"><b>' + esc(x.name) + '</b><small>' + x.activeJobs + ' ' + esc(t('jobs')) + ' · ' +
        esc(x.hoursToday > 0 ? fmt(t('busyTech'), num(x.hoursToday)) : t('freeTech')) + '</small>' +
        '<span class="sb-load"><span style="width:' + load + '%"></span></span></span></button>';
    }).join('');
  }

  function renderBoard() {
    var list = visibleOrders();
    var filtered = !!(state.q || state.tech || state.kpi);
    var html = '';
    if (filtered) {
      html += '<div class="sb-filterbar"><span>' + list.length + ' / ' + orders().length + '</span>' +
        '<button type="button" class="sb-link" data-action="clear">' + esc(t('clear')) + '</button></div>';
    }
    if (state.data.truncated) {
      html += '<div class="sb-note">' + esc(fmt(t('truncated'), orders().length)) + '</div>';
    }
    if (!state.data.canAssign) {
      html += '<div class="sb-note">' + esc(t('noAssignRight')) + '</div>';
    }
    html += '<div class="sb-columns">' + COLUMNS.map(function (col) {
      var cards = list.filter(function (o) { return col.stages.indexOf(o.stage) >= 0; }).sort(compareOrders);
      return '<section class="sb-col col-' + col.key + '">' +
        '<header class="sb-col-head"><span class="sb-dot"></span><span class="sb-col-title">' + esc(t(col.title)) + '</span>' +
        '<span class="sb-count">' + cards.length + '</span><small>' + esc(t(col.hint)) + '</small></header>' +
        '<div class="sb-col-body">' +
        (cards.length ? cards.map(cardHtml).join('') : '<div class="sb-empty">' + esc(filtered ? t('noMatch') : t('empty')) + '</div>') +
        '</div></section>';
    }).join('') + '</div>';
    var scroll = saveScroll();
    els.main.innerHTML = html;
    restoreScroll(scroll);
  }

  function cardHtml(o) {
    var today = state.data.today;
    var items = o.items || [];
    var first = items[0];
    var techs = o.technicians || [];
    var when = whenText(o, today);
    var html = '<article class="sb-card pr-' + esc(o.priority) + (o.overdue ? ' is-late' : '') + '" data-action="open" data-no="' + esc(o.no) + '" tabindex="0">';
    html += '<div class="sb-card-top"><span class="sb-no">' + esc(o.no) + '</span>' +
      '<span class="sb-pill pr">' + esc(t(o.priority)) + '</span>' +
      (o.overdue ? '<span class="sb-pill late">' + esc(t('late')) + '</span>' : '') + '</div>';
    html += '<div class="sb-cust">' + esc(o.name || o.customerNo) + '</div>';
    if (o.description) { html += '<div class="sb-desc">' + esc(o.description) + '</div>'; }
    if (first) {
      html += '<div class="sb-item">' + esc([first.serviceItemNo, first.description].filter(Boolean).join(' · ')) +
        (items.length > 1 ? ' <span class="sb-more">' + esc(fmt(t('moreItems'), items.length - 1)) + '</span>' : '') + '</div>';
    }
    var tags = '';
    if (o.city) { tags += '<span class="sb-tag city">' + esc(o.city) + '</span>'; }
    if (first && first.repairStatus && !isDone(o)) {
      tags += '<span class="sb-tag status" title="' + esc(first.repairStatus) + '">' + esc(first.repairStatusText || first.repairStatus) + '</span>';
    }
    if (o.stage === 'toship') { tags += '<span class="sb-tag toship">' + esc(t('toShip')) + '</span>'; }
    if (o.stage === 'toinvoice') { tags += '<span class="sb-tag toinvoice">' + esc(t('toInvoice')) + '</span>'; }
    if (tags) { html += '<div class="sb-tags">' + tags + '</div>'; }

    var canAssign = state.data.canAssign && !isDone(o) && items.length > 0;
    html += '<div class="sb-card-foot"><div class="sb-who">';
    if (techs.length) {
      html += techs.slice(0, 3).map(function (n) { return avatar(n, 'sm'); }).join('');
      if (canAssign) {
        html += '<button type="button" class="sb-add" data-action="assign" data-no="' + esc(o.no) + '" title="' + esc(t('addTech')) + '" aria-label="' + esc(t('addTech')) + '">+</button>';
      }
      html += '<span class="sb-who-names">' + esc(techs.join(', ')) + (o.hours > 0 && !isDone(o) ? ' · ' + num(o.hours) + ' ' + esc(t('hourShort')) : '') + '</span>';
    } else {
      html += '<span class="sb-muted">' + esc(t('notAssigned')) + '</span>';
    }
    html += '</div>';
    if (when && !isDone(o)) {
      html += '<span class="sb-when' + (o.overdue ? ' late' : (o.responseDate === today ? ' today' : '')) + '" title="' + esc(t('response')) + '">' + esc(when) + '</span>';
    }
    html += '</div>';
    if (canAssign && !techs.length) {
      html += '<button type="button" class="sb-btn primary sb-card-btn" data-action="assign" data-no="' + esc(o.no) + '">' + esc(t('assign')) + '</button>';
    }
    html += '</article>';
    return html;
  }

  function saveScroll() {
    var cols = els.main.querySelectorAll('.sb-col-body');
    var out = { x: 0, cols: [] };
    var wrap = els.main.querySelector('.sb-columns');
    if (wrap) { out.x = wrap.scrollLeft; }
    for (var i = 0; i < cols.length; i++) { out.cols.push(cols[i].scrollTop); }
    return out;
  }
  function restoreScroll(s) {
    var wrap = els.main.querySelector('.sb-columns');
    if (wrap) { wrap.scrollLeft = s.x; }
    var cols = els.main.querySelectorAll('.sb-col-body');
    for (var i = 0; i < cols.length && i < s.cols.length; i++) { cols[i].scrollTop = s.cols[i]; }
  }

  // ---- assign dialog ----------------------------------------------------
  function findOrder(no) {
    var list = orders();
    for (var i = 0; i < list.length; i++) { if (list[i].no === no) { return list[i]; } }
    return null;
  }
  function openDialog(no) {
    var o = findOrder(no);
    if (!o) { return; }
    var items = o.items || [];
    state.dialog = {
      no: o.no,
      itemLine: items.length ? items[0].lineNo : 0,
      tech: '',
      date: state.data.today,
      hours: '1',
      busy: false,
      error: ''
    };
    renderDialog();
  }
  function closeDialog() {
    state.dialog = null;
    renderDialog();
  }
  function renderDialog() {
    var d = state.dialog;
    if (!d) {
      els.dialog.className = 'sb-dialog-wrap';
      els.dialog.innerHTML = '';
      return;
    }
    var o = findOrder(d.no);
    if (!o) { closeDialog(); return; }
    var items = o.items || [];
    var techs = technicians();
    var html = '<div class="sb-dialog" role="dialog" aria-modal="true" aria-labelledby="sb-dlg-title">';
    html += '<h2 id="sb-dlg-title">' + esc(t('dlgTitle')) + '</h2>';
    html += '<p class="sb-dlg-sub"><b>' + esc(o.no) + '</b> · ' + esc(o.name) + (o.description ? '<br>' + esc(o.description) : '') + '</p>';
    if (items.length > 1) {
      html += '<label class="sb-field"><span>' + esc(t('serviceItem')) + '</span><select data-field="itemLine"' + (d.busy ? ' disabled' : '') + '>' +
        items.map(function (i) {
          return '<option value="' + i.lineNo + '"' + (i.lineNo === d.itemLine ? ' selected' : '') + '>' +
            esc([i.serviceItemNo, i.description].filter(Boolean).join(' · ') || i.lineNo) + '</option>';
        }).join('') + '</select></label>';
    } else if (items.length === 1) {
      html += '<div class="sb-field"><span>' + esc(t('serviceItem')) + '</span><div class="sb-static">' +
        esc([items[0].serviceItemNo, items[0].description].filter(Boolean).join(' · ')) + '</div></div>';
    }
    html += '<div class="sb-field"><span>' + esc(t('technician')) + '</span>';
    if (!techs.length) {
      html += '<div class="sb-static">' + esc(t('noTechs')) + '</div>';
    } else {
      html += '<div class="sb-pick">' + techs.map(function (x) {
        var sel = d.tech === x.user;
        return '<button type="button" class="sb-pick-row' + (sel ? ' is-selected' : '') + '" data-action="pick" data-user="' + esc(x.user) + '"' +
          (d.busy ? ' disabled' : '') + ' aria-pressed="' + sel + '">' + avatar(x.name) +
          '<span><b>' + esc(x.name) + '</b><small>' + x.activeJobs + ' ' + esc(t('jobs')) + ' · ' +
          esc(x.hoursToday > 0 ? fmt(t('busyTech'), num(x.hoursToday)) : t('freeTech')) + '</small></span>' +
          '<span class="sb-check" aria-hidden="true"></span></button>';
      }).join('') + '</div>';
    }
    html += '</div>';
    html += '<div class="sb-row2">' +
      '<label class="sb-field"><span>' + esc(t('date')) + '</span><input type="date" data-field="date" value="' + esc(d.date) + '"' + (d.busy ? ' disabled' : '') + '></label>' +
      '<label class="sb-field"><span>' + esc(t('hours')) + '</span><input type="number" min="0.25" step="0.25" inputmode="decimal" data-field="hours" value="' + esc(d.hours) + '"' + (d.busy ? ' disabled' : '') + '></label>' +
      '</div>';
    if (d.error) { html += '<div class="sb-error" role="alert">' + esc(d.error) + '</div>'; }
    html += '<div class="sb-dlg-actions"><button type="button" class="sb-btn ghost" data-action="cancel"' + (d.busy ? ' disabled' : '') + '>' + esc(t('cancel')) + '</button>' +
      '<button type="button" class="sb-btn primary" data-action="confirm"' + (d.busy || !techs.length ? ' disabled' : '') + '>' +
      esc(d.busy ? t('assigning') : t('doAssign')) + '</button></div>';
    html += '</div>';
    els.dialog.className = 'sb-dialog-wrap is-open';
    els.dialog.innerHTML = html;
  }
  function confirmDialog() {
    var d = state.dialog;
    if (!d || d.busy) { return; }
    var hours = parseFloat(String(d.hours).replace(',', '.'));
    if (!d.tech) { d.error = t('pickTech'); renderDialog(); return; }
    if (!d.date) { d.error = t('badDate'); renderDialog(); return; }
    if (!(hours > 0)) { d.error = t('badHours'); renderDialog(); return; }
    d.busy = true;
    d.error = '';
    d.pending = true;
    renderDialog();
    if (assignTimer) { clearTimeout(assignTimer); }
    assignTimer = setTimeout(function () {
      if (state.dialog && state.dialog.pending) {
        state.dialog.pending = false;
        state.dialog.busy = false;
        state.dialog.error = t('noReply');
        renderDialog();
      }
    }, 30000);
    invoke('AssignTechnician', [d.no, Number(d.itemLine) || 0, d.tech, d.date, String(hours)]);
  }

  // One refresh at a time: focus, timer and button clicks must not queue several server rebuilds.
  function requestRefresh() {
    if (state.refreshAt && Date.now() - state.refreshAt < 20000) { return; }
    state.refreshAt = Date.now();
    invoke('RequestRefresh', []);
  }

  // ---- toast ------------------------------------------------------------
  function toast(text, isError) {
    els.toast.textContent = text;
    els.toast.className = 'sb-toast is-open' + (isError ? ' is-error' : '');
    if (toastTimer) { clearTimeout(toastTimer); }
    toastTimer = setTimeout(function () { els.toast.className = 'sb-toast'; }, isError ? 7000 : 3500);
  }

  // ---- events -----------------------------------------------------------
  function onClick(ev) {
    var el = ev.target.closest ? ev.target.closest('[data-action]') : null;
    if (!el || !els.root.contains(el)) { return; }
    var action = el.getAttribute('data-action');
    switch (action) {
      case 'kpi':
        state.kpi = state.kpi === el.getAttribute('data-key') ? '' : el.getAttribute('data-key');
        render();
        break;
      case 'tech':
        state.tech = state.tech === el.getAttribute('data-user') ? '' : el.getAttribute('data-user');
        els.techSelect.value = state.tech;
        render();
        break;
      case 'clear':
        state.q = ''; state.tech = ''; state.kpi = '';
        els.search.value = ''; els.techSelect.value = '';
        render();
        break;
      case 'refresh':
        requestRefresh();
        break;
      case 'open':
        invoke('OpenOrder', [el.getAttribute('data-no')]);
        break;
      case 'assign':
        ev.stopPropagation();
        openDialog(el.getAttribute('data-no'));
        break;
      case 'pick':
        if (state.dialog && !state.dialog.busy) { state.dialog.tech = el.getAttribute('data-user'); state.dialog.error = ''; renderDialog(); }
        break;
      case 'cancel':
        closeDialog();
        break;
      case 'confirm':
        confirmDialog();
        break;
      case 'backdrop':
        if (ev.target === el && state.dialog && !state.dialog.busy) { closeDialog(); }
        break;
    }
  }
  function onDialogInput(ev) {
    var field = ev.target.getAttribute && ev.target.getAttribute('data-field');
    if (!field || !state.dialog) { return; }
    state.dialog[field] = field === 'itemLine' ? Number(ev.target.value) : ev.target.value;
    if (state.dialog.error) { state.dialog.error = ''; }
  }
  function onKey(ev) {
    if (ev.key === 'Escape' && state.dialog && !state.dialog.busy) { closeDialog(); return; }
    if ((ev.key === 'Enter' || ev.key === ' ') && ev.target.classList && ev.target.classList.contains('sb-card')) {
      ev.preventDefault();
      invoke('OpenOrder', [ev.target.getAttribute('data-no')]);
    }
  }

  function buildTechOptions() {
    var html = '<option value="">' + esc(t('allTechs')) + '</option>';
    html += technicians().map(function (x) {
      return '<option value="' + esc(x.user) + '"' + (state.tech === x.user ? ' selected' : '') + '>' + esc(x.name) + '</option>';
    }).join('');
    els.techSelect.innerHTML = html;
  }

  function init() {
    if (els.root) { return; }
    var host = document.getElementById('controlAddIn') || document.body;
    host.innerHTML =
      '<div class="sb">' +
      '<div class="sb-top">' +
      '<div class="sb-kpis" role="group"></div>' +
      '<div class="sb-tools">' +
      '<label class="sb-search"><svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="8.5" cy="8.5" r="5.5"/><path d="M13 13l4 4"/></svg><input type="search" autocomplete="off"></label>' +
      '<select class="sb-select"></select>' +
      '</div></div>' +
      '<div class="sb-techs"></div>' +
      '<div class="sb-main"></div>' +
      '<div class="sb-dialog-wrap" data-action="backdrop"></div>' +
      '<div class="sb-toast" role="status" aria-live="polite"></div>' +
      '</div>';
    els.root = host.querySelector('.sb');
    els.kpis = host.querySelector('.sb-kpis');
    els.techs = host.querySelector('.sb-techs');
    els.main = host.querySelector('.sb-main');
    els.dialog = host.querySelector('.sb-dialog-wrap');
    els.toast = host.querySelector('.sb-toast');
    els.search = host.querySelector('.sb-search input');
    els.techSelect = host.querySelector('.sb-select');

    els.root.addEventListener('click', onClick);
    els.root.addEventListener('keydown', onKey);
    els.dialog.addEventListener('input', onDialogInput);
    els.dialog.addEventListener('change', onDialogInput);
    els.search.addEventListener('input', function () { state.q = els.search.value.trim(); renderBoard(); });
    els.techSelect.addEventListener('change', function () { state.tech = els.techSelect.value; render(); });

    // Keep the board current while it stays open (new orders, technician progress from the terminal).
    setInterval(function () {
      if (document.visibilityState === 'visible' && !state.dialog && Date.now() - state.lastData > 55000) {
        requestRefresh();
      }
    }, 60000);
    window.addEventListener('focus', function () {
      if (!state.dialog && state.lastData && Date.now() - state.lastData > 15000) { requestRefresh(); }
    });
    buildTechOptions();
    render();
  }

  // ---- AL procedures -----------------------------------------------------
  window.SetLocale = function (code) {
    var c = String(code || '');
    state.locale = (c.replace(/\D/g, '') === '1055' || /^tr/i.test(c)) ? 'tr' : 'en';
    if (els.root) { buildTechOptions(); render(); renderDialog(); }
  };
  window.SetData = function (json) {
    var parsed;
    try { parsed = JSON.parse(json); } catch (e) { parsed = { orders: [], technicians: [], today: '' }; }
    state.data = parsed;
    state.lastData = Date.now();
    state.refreshAt = 0;
    if (state.tech && !techByUser(state.tech)) { state.tech = ''; }
    if (els.root) { buildTechOptions(); render(); renderDialog(); }
  };
  // Called by AL only after the assignment really succeeded (errors arrive through ShowMessage).
  window.AssignDone = function () {
    if (assignTimer) { clearTimeout(assignTimer); assignTimer = null; }
    if (state.dialog) { state.dialog = null; renderDialog(); }
    toast(t('assigned'), false);
  };
  window.ShowMessage = function (text, isError) {
    if (assignTimer) { clearTimeout(assignTimer); assignTimer = null; }
    if (state.dialog && state.dialog.pending) {
      state.dialog.busy = false;
      state.dialog.pending = false;
      state.dialog.error = text;
      renderDialog();
      return;
    }
    toast(text, !!isError);
  };

  window.DOPSWHSServiceBoard = { init: init };
})();
