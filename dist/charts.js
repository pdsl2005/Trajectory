'use strict';

const TrajectoryCharts = (() => {
  const usd = new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', maximumFractionDigits: 0
  });
  const compact = new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 1
  });
  const money = value => Number.isFinite(value) ? usd.format(Math.round(value) || 0) : '—';
  const shortMoney = value => Number.isFinite(value) ? compact.format(value || 0) : '—';
  const escape = value => String(value).replace(/[&<>"']/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[char]));
  const dashes = ['', '7 4', '2 4', '10 4 2 4', '4 3', '13 4'];

  function axis(values, target = 4) {
    let min = Math.min(0, ...values);
    let max = Math.max(0, ...values);
    if (min === max) max = 1;
    const raw = Math.max(1, (max - min) / target);
    const magnitude = 10 ** Math.floor(Math.log10(raw));
    const step = [1, 2, 2.5, 5, 10].find(unit => unit * magnitude >= raw) * magnitude;
    min = Math.floor(min / step) * step;
    max = Math.ceil(max / step) * step;
    const ticks = Array.from({ length: Math.round((max - min) / step) + 1 },
      (_, index) => min + index * step);
    return { min, max, ticks };
  }

  function linePath(values, x, y) {
    let drawing = false;
    return values.map((value, index) => {
      if (!Number.isFinite(value)) {
        drawing = false;
        return '';
      }
      const command = drawing ? 'L' : 'M';
      drawing = true;
      return command + x(index) + ',' + y(value);
    }).join(' ');
  }

  function csvText(periods, series, primary) {
    const fields = ['Year', 'Age', ...series.map(item => item.label + (item.point || item.band ? '' : ' median'))];
    if (primary) fields.push('P10', 'P25', 'P75', 'P90');
    const csvField = value => '"' + String(value ?? '').replaceAll('"', '""') + '"';
    const header = fields.map(csvField).join(',');
    const body = periods.map((period, i) => {
      const values = series.map(item => item.values[i]?.[2]);
      if (primary) values.push(...[0, 1, 3, 4].map(q => primary.values[i]?.[q]));
      return [period.year, period.age, ...values]
        .map(value => Number.isFinite(value) ? Math.round(value) : '').join(',');
    });
    return [header, ...body].join('\n');
  }

  function mount(host, config) {
    const { periods, series, title, units, download, showTable = true, annotation } = config;
    const hidden = new Set();
    const last = periods.length - 1;
    let selected = Math.max(0, Math.min(last, config.initialIndex ?? last));
    let bands = Boolean(series.find(item => item.band));
    let currentX = index => index;

    host.innerHTML = `
      <div class="chart-layout">
        <div class="chart-body">
          <div class="chart-legend" aria-label="Chart series">
            ${series.map((item, index) => `<button type="button" class="series-toggle" data-series="${index}" aria-pressed="true">
              <svg aria-hidden="true" width="24" height="12"><path d="M1 6H23" stroke-width="2.5" stroke="var(--series-${item.color})" stroke-dasharray="${item.dash || dashes[index]}"/></svg>
              ${escape(item.label)}
            </button>`).join('')}
            ${bands ? '<button type="button" class="series-toggle band-toggle" aria-pressed="true"><span class="band-swatch" aria-hidden="true"></span>Percentile bands</button>' : ''}
          </div>
          <div class="chart-plane">
            <svg class="plot" role="img" aria-label="${escape(title)}, amounts in ${escape(units)}"></svg>
          </div>
          <div class="chart-scrub">
            <button type="button" class="chart-prev" aria-label="Previous year">‹</button>
            <label class="chart-range-wrap"><span class="sr-only">Inspect forecast year</span><input class="chart-range" type="range" min="0" max="${last}" value="${selected}" step="1"></label>
            <button type="button" class="chart-next" aria-label="Next year">›</button>
          </div>
        </div>
        <aside class="chart-detail" aria-label="Selected year values">
          <p class="detail-caption">Selected year</p>
          <h3 class="detail-year"></h3>
          <div class="detail-values"></div>
          ${annotation ? '<div class="detail-annotation"></div>' : ''}
          <p class="detail-units">${escape(units)}</p>
        </aside>
      </div>
      ${showTable ? `<details class="chart-data">
        <summary>View annual data</summary>
        <div class="chart-table-actions">
          <p class="muted">Amounts in ${escape(units)}</p>
          ${download ? '<button type="button" class="chart-export">Export chart CSV</button>' : ''}
        </div>
        <div class="table-scroll" role="region" aria-label="${escape(title)} data" tabindex="0"></div>
      </details>` : ''}
    `;

    const svg = host.querySelector('.plot');
    const plane = host.querySelector('.chart-plane');
    const range = host.querySelector('.chart-range');
    const previous = host.querySelector('.chart-prev');
    const next = host.querySelector('.chart-next');
    const detailYear = host.querySelector('.detail-year');
    const detailValues = host.querySelector('.detail-values');
    const detailAnnotation = host.querySelector('.detail-annotation');
    const toggles = [...host.querySelectorAll('[data-series]')];
    const primary = () => series.find((item, index) => item.band && !hidden.has(index));
    const visible = () => series.filter((item, index) => !hidden.has(index));

    function graph() {
      const width = Math.max(250, Math.round(plane.clientWidth));
      const height = width < 420 ? 224 : 282;
      const left = 57, right = 18, top = 15, bottom = 33;
      const x = index => left + index / Math.max(1, last) * (width - left - right);
      currentX = x;
      const highlight = bands ? primary() : undefined;
      const domain = visible().flatMap(item => item.values.flatMap(value =>
        item === highlight ? [value?.[0], value?.[4]] : [value?.[2]])).filter(Number.isFinite);
      const scale = axis(domain);
      const y = value => top + (scale.max - value) / (scale.max - scale.min) * (height - top - bottom);
      const floor = height - bottom;
      svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
      svg.style.height = height + 'px';
      const grid = scale.ticks.map(value => `
        <line class="${value === 0 ? 'plot-zero' : 'plot-grid'}" x1="${left}" x2="${width - right}" y1="${y(value)}" y2="${y(value)}"/>
        <text class="plot-tick" x="${left - 8}" y="${y(value) + 4}" text-anchor="end">${shortMoney(value)}</text>
      `).join('');
      const labelStep = Math.max(1, Math.ceil(last / Math.max(2, Math.floor((width - left - right) / 62))));
      const labels = periods.map((period, index) => {
        if (index !== last && (index % labelStep || last - index < labelStep * .68)) return '';
        const anchor = index === 0 ? 'start' : index === last ? 'end' : 'middle';
        return `<text class="plot-tick" x="${x(index)}" y="${floor + 23}" text-anchor="${anchor}">${period.year}</text>`;
      }).join('');
      const area = (low, high, style) => {
        const values = highlight.values;
        const upper = values.map((sample, index) => `${x(index)},${y(sample[high])}`);
        const lower = values.map((sample, index) => `${x(index)},${y(sample[low])}`).reverse();
        return `<polygon class="${style}" points="${[...upper, ...lower].join(' ')}"/>`;
      };
      const uncertainty = highlight ? area(0, 4, 'band-outer') + area(1, 3, 'band-inner') : '';
      const lines = series.map((item, index) => {
        if (hidden.has(index)) return '';
        const values = item.values.map(value => value?.[2]);
        const points = values.map((value, i) => Number.isFinite(value)
          ? `<circle class="plot-point" cx="${x(i)}" cy="${y(value)}" r="2" fill="var(--series-${item.color})"/>` : '').join('');
        return `<path d="${linePath(values, x, y)}" fill="none" stroke="var(--series-${item.color})"
          stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="${item.dash || dashes[index]}"/>${points}`;
      }).join('');
      const markers = visible().map(item => {
        const value = item.values[selected]?.[2];
        return Number.isFinite(value) ? `<circle class="plot-selected" cx="${x(selected)}" cy="${y(value)}"
          r="4.5" fill="var(--series-${item.color})"/>` : '';
      }).join('');
      svg.innerHTML = grid + uncertainty + labels +
        `<line class="plot-cursor" x1="${x(selected)}" x2="${x(selected)}" y1="${top}" y2="${floor}"/>` + lines + markers;
    }

    function detail() {
      const { year, age } = periods[selected];
      const itemSummary = item => {
        const values = item.values[selected];
        const span = values && !item.point && values[0] !== values[4]
          ? `<span class="detail-range">P10–P90 · ${money(values[0])} to ${money(values[4])}</span>` : '';
        return `<div class="detail-row"><span><i class="series-dot" style="--dot:var(--series-${item.color})"></i>${escape(item.label)}</span>
          <strong>${money(values?.[2])}</strong>${span}</div>`;
      };
      detailYear.innerHTML = `${year} <span>Age ${age}</span>`;
      detailValues.innerHTML = visible().map(itemSummary).join('');
      if (annotation) {
        detailAnnotation.innerHTML = annotation(periods[selected]).map(([label, value]) =>
          `<div><span>${escape(label)}</span>${value ? `<strong>${escape(value)}</strong>` : ''}</div>`).join('');
      }
      previous.disabled = selected === 0;
      next.disabled = selected === last;
      range.value = selected;
      range.setAttribute('aria-valuetext', year + ', age ' + age);
    }

    function table() {
      const box = host.querySelector('.table-scroll');
      if (!box) return;
      const active = visible();
      const ribbon = primary();
      const head = active.map(item => `<th scope="col">${escape(item.label)}${item.point || item.band ? '' : ' median'}</th>`).join('') +
        (ribbon ? '<th scope="col">P10</th><th scope="col">P25</th><th scope="col">P75</th><th scope="col">P90</th>' : '');
      const rows = periods.map((period, index) => {
        const values = active.map(item => item.values[index]?.[2]);
        if (ribbon) values.push(...[0, 1, 3, 4].map(q => ribbon.values[index]?.[q]));
        return `<tr><th scope="row">${period.year}</th><td>${period.age}</td>${values.map(value => `<td>${money(value)}</td>`).join('')}</tr>`;
      }).join('');
      box.innerHTML = `<table><caption class="sr-only">${escape(title)} annual values</caption>
        <thead><tr><th scope="col">Year</th><th scope="col">Age</th>${head}</tr></thead><tbody>${rows}</tbody></table>`;
    }

    function select(index) {
      const value = Math.max(0, Math.min(last, index));
      if (value === selected) return;
      selected = value;
      graph();
      detail();
    }
    function pointer(event) {
      const box = svg.getBoundingClientRect();
      const localX = (event.clientX - box.left) * svg.viewBox.baseVal.width / box.width;
      const first = currentX(0);
      const step = (currentX(last) - first) / Math.max(1, last);
      select(step > 0 ? Math.round((localX - first) / step) : 0);
    }
    svg.addEventListener('pointermove', event => {
      if (event.pointerType === 'mouse') pointer(event);
    });
    svg.addEventListener('click', pointer);
    range.addEventListener('input', () => select(Number(range.value)));
    previous.onclick = () => select(selected - 1);
    next.onclick = () => select(selected + 1);
    toggles.forEach((button, index) => {
      button.onclick = () => {
        if (hidden.has(index)) hidden.delete(index);
        else if (hidden.size < series.length - 1) hidden.add(index);
        button.setAttribute('aria-pressed', String(!hidden.has(index)));
        graph();
        detail();
        table();
      };
    });
    const bandButton = host.querySelector('.band-toggle');
    if (bandButton) bandButton.onclick = () => {
      bands = !bands;
      bandButton.setAttribute('aria-pressed', String(bands));
      graph();
    };
    const exportButton = host.querySelector('.chart-export');
    if (exportButton) exportButton.onclick = () => download(csvText(periods, visible(), primary()));

    graph();
    detail();
    table();
    const observer = new ResizeObserver(graph);
    observer.observe(plane);
    return () => observer.disconnect();
  }

  return { mount, money, shortMoney, escape, axis, linePath, csvText };
})();

if (typeof module !== 'undefined') module.exports = TrajectoryCharts;
