(() => {
'use strict';

const E = Trajectory;
const Chart = TrajectoryCharts;
const { money, escape } = Chart;
const $ = id => document.getElementById(id);
const tabs = [['Overview','overview'], ['Budget','budget'], ['Plan','plan'], ['Forecast','forecast'], ['Settings','settings']];
const icons = {
  overview: '<path d="M3 10.5 12 3l9 7.5V21H3z"/><path d="M9 21v-7h6v7"/>',
  budget: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18m-14 5h3"/>',
  forecast: '<path d="M3 3v18h18M7 15l4-5 4 2 5-6"/><circle cx="20" cy="6" r="1.5"/>',
  plan: '<path d="M3 21V5m0 1h14l-3 4 3 4H3"/>',
  career: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V4h8v3M3 13h18m-11 0v3h4v-3"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M5 19l2-2M17 7l2-2"/>'
};
const forecastViews = {
  wealth: { label: 'Net worth', title: 'Net worth projection', description: 'Total assets less modeled debt.' },
  accessible: { label: 'Accessible wealth', title: 'Accessible wealth projection', description: 'Cash and brokerage minus modeled debt.' },
  accounts: { label: 'Account balances', title: 'Account balances', description: 'Year-end balances. Each line shows the median for that account.' },
  cashflow: { label: 'Annual cash flow', title: 'Annual cash flow', description: 'Surplus is gross income less employee 401(k) contributions, estimated taxes and expenses.' },
  investments: { label: 'Savings & contributions', title: 'Savings and contributions', description: 'Amounts contributed during each year. Cash reserve top-ups are reflected in account balances.' },
  roth: { label: 'Roth IRA eligibility', title: 'Roth IRA eligibility', description: 'Modeled modified adjusted gross income and the estimated direct-contribution phaseout.' },
  rothAmounts: { label: 'Roth IRA contributions', title: 'Roth IRA contributions', description: 'Projected direct and backdoor contributions. The direct limit shown is per person.' },
  debt: { label: 'Debt & shortfalls', title: 'Debt and shortfalls', description: 'Shortfall measures a cash-flow deficit before drawing down accounts. Debt is the remaining balance at year end.' }
};
const route = () => {
  const name = location.hash.slice(1);
  return name === 'career' || tabs.some(([, key]) => key === name) ? name : 'overview';
};
let state, database, tab = route(), house = false, storageError = '', pending = 0, offline = '';
let queue = Promise.resolve(), cache = new Map(), disposeCharts = [];
let forecastView = 'wealth', timeframe = 'full', real = false, compare = '';

const plan = () => state.plans[state.active];
const svgIcon = key => `<svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${icons[key]}</svg>`;
const card = (title, body, extra = '') => `<section class="card ${extra}"><h2>${title}</h2>${body}</section>`;
const row = (label, value) => `<div class="value-row"><span>${label}</span><strong>${value}</strong></div>`;
const metric = (label, value, note = '') => `<div class="metric"><p>${label}</p><strong>${value}</strong>${note ? `<small>${note}</small>` : ''}</div>`;
const heading = (title, description = '') => `<div class="page-heading"><h1>${title}</h1>${description ? `<p>${description}</p>` : ''}</div>`;

function field(key, label, min = 0, max = 1000000, step = 1, suffix = '') {
  return `<div class="value-row">
    <label for="f-${key}">${label}${suffix ? ` <span>(${suffix})</span>` : ''}</label>
    <input id="f-${key}" type="number" inputmode="${step < 1 ? 'decimal' : 'numeric'}"
      data-field="${key}" min="${min}" max="${max}" step="${step}" value="${plan()[key]}">
  </div>`;
}
const fields = configs => configs.map(config => field(...config)).join('');
const check = (key, label) => `<div class="value-row"><label for="f-${key}">${label}</label><input id="f-${key}" type="checkbox" data-field="${key}" ${plan()[key] ? 'checked' : ''}></div>`;
const select = (id, label, options, value) => `<label class="select-control" for="${id}"><span>${label}</span>
  <select id="${id}">${options.map(([key, text]) => `<option value="${escape(key)}" ${key === value ? 'selected' : ''}>${escape(text)}</option>`).join('')}</select></label>`;
const scopeToggle = () => `<div class="segmented" role="group" aria-label="Forecast scope">
  <button type="button" data-scope="individual" aria-pressed="${!house}">Individual</button>
  <button type="button" data-scope="household" aria-pressed="${house}">Household</button>
</div>`;

function status() {
  $('storage').textContent = storageError || (pending ? 'Saving…' : state ? 'Saved on this device' : '');
  $('storage').classList.toggle('error', Boolean(storageError));
}

function save(update) {
  pending++;
  storageError = '';
  status();
  queue = queue.then(async () => {
    try {
      state = await database.update(update);
      storageError = '';
      cache.clear();
    } catch (error) {
      storageError = 'Couldn’t save this change. Your previous plans are still available.';
      console.error(error);
    } finally {
      pending--;
      if (state || !storageError) render();
      else {
        const submit = $('setup')?.querySelector('button[type="submit"]');
        if (submit) submit.disabled = false;
        status();
      }
    }
  });
  return queue;
}

function existingPlan(current, name) {
  if (!Object.hasOwn(current.plans, name)) throw new Error('This scenario no longer exists.');
  return current.plans[name];
}

function projections(name = state.active, mode = 'base') {
  const key = JSON.stringify([name, mode]);
  if (!cache.has(key)) {
    const settings = state.plans[name];
    const options = mode === 'optimistic'
      ? { n: 1, det: true, returnOverride: settings.optimistic } : { mode };
    cache.set(key, E.simulate(settings, options));
  }
  return cache.get(key);
}

function download(name, data, type) {
  const link = document.createElement('a');
  link.href = URL.createObjectURL(new Blob([data], { type }));
  link.download = name;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(link.href), 30000);
}

function downloadForecast() {
  const rows = projections();
  const keys = Object.keys(rows[0]).filter(key => Array.isArray(rows[0][key]));
  const header = ['year', 'age', ...keys.flatMap(key => ['P10','P25','P50','P75','P90'].map(q => key + '_' + q))];
  const body = rows.map(period => [period.year, period.age, ...keys.flatMap(key => period[key].map(Math.round))]);
  download('trajectory-forecast.csv', [header, ...body].map(values => values.join(',')).join('\n'), 'text/csv');
}

function chartSeries(rows, key, label, color, options = {}) {
  const { baseline, ...style } = options;
  return {
    label, color, ...style,
    values: rows.map(period => {
      const sample = period?.[key];
      return sample && (baseline
        ? sample.map(value => value / (1 + plan().inflation / 100) ** (period.year - baseline))
        : sample);
    })
  };
}

function netWorthSeries(rows, key, options = {}) {
  const { baseline, comparison } = options;
  const years = rows.map(row => row.year);
  const align = data => {
    const map = new Map(data.map(row => [row.year, row]));
    return years.map(year => map.get(year));
  };
  return [
    chartSeries(rows, key, 'Median', 'violet', { band: true, baseline }),
    chartSeries(align(projections(state.active, 'optimistic')), key, 'Optimistic path', 'teal', { point: true, dash: '7 4', baseline }),
    ...(comparison ? [chartSeries(align(projections(comparison)), key, comparison, 'amber', { baseline })] : [])
  ];
}

function mountChart(id, config) {
  const full = { units: 'nominal USD', ...config };
  return Chart.mount($(id), full);
}

function overview() {
  const all = projections();
  const first = all[0], last = all.at(-1);
  const key = house ? 'house' : 'individual';
  const accessible = house ? 'houseAccessible' : 'accessible';
  const settings = plan(), budget = E.plan(settings);
  const upcoming = [[settings.marriage,'Marriage'], [settings.firstChild,'First child'], [settings.secondChild,'Second child']]
    .filter(([age]) => age >= first.age && age <= last.age)
    .sort((a, b) => a[0] - b[0]).map(([age, label]) => row(label, `${first.year + age - first.age} · age ${age}`)).join('');
  return heading('Overview', escape(state.active) + ' · ' + first.year + '–' + last.year) + scopeToggle() +
    `<div class="metrics">
      ${metric('Starting assets', money(settings.assets))}
      ${metric('Annual salary', money(settings.salary))}
      ${metric(`${last.year} median net worth`, money(last[key][2]), 'Nominal dollars')}
      ${metric(`${last.year} median accessible`, money(last[accessible][2]), 'Cash and brokerage less debt')}
    </div>` +
    `<div class="plan-entry"><div><strong>Planning ahead?</strong><p>Explore retirement and major expenses.</p></div><button type="button" data-go="plan">Open Plan</button></div>` +
    card('Wealth trajectory', '<p class="chart-note">The shaded bands show the middle 50% and 80% of simulated outcomes.</p><div id="overview-chart"></div>') +
    `<div class="two-column">${card('Monthly budget', row('Take-home after 401(k)', money(budget.net)) +
      row('Living costs', money(budget.spend)) + row('IRA target', money(budget.ira / 12)) +
      row('Available for brokerage', money(budget.broker)))}
    ${upcoming ? card('Life events in this forecast', upcoming) : ''}</div>`;
}

const spendingFields = [
  ['rent','Housing',0,100000,1,'$'], ['food','Food & dining',0,100000,1,'$'],
  ['utilities','Utilities',0,100000,1,'$'], ['transport','Transportation',0,100000,1,'$'],
  ['goods','Personal goods',0,100000,1,'$'], ['entertainment','Entertainment',0,100000,1,'$'],
  ['medical','Medical',0,100000,1,'$'], ['renters','Renters insurance',0,100000,1,'$'],
  ['travel','Travel',0,100000,1,'$'], ['misc','Other spending',0,100000,1,'$']
];
function budget() {
  const settings = plan(), amounts = E.plan(settings);
  const buckets = spendingFields.map(([key, label]) => ({ label, value: settings[key] }))
    .filter(item => item.value > 0).sort((a, b) => b.value - a.value);
  const fee = settings.goldFee / 12;
  if (fee > 0) buckets.push({ label: 'Annual IRA program fee', value: fee });
  return heading('Monthly budget', 'Based on a full year of individual income and spending.') +
    `<div class="metrics">
      ${metric('Take-home pay', money(amounts.net), 'After estimated taxes and 401(k)')}
      ${metric('Monthly spending', money(amounts.spend))}
      ${metric('Available for brokerage', money(amounts.broker), 'After IRA target, before reserve top-up')}
      ${metric('Cash reserve target', money(amounts.target))}
    </div>` +
    `<div class="two-column">${card('Monthly allocation', row('Gross pay', money(amounts.g / 12)) +
      row('Estimated taxes', money(amounts.tax / 12)) + row('Traditional 401(k)', money(amounts.c / 12)) +
      row('IRA target', money(amounts.ira / 12)) + row('Employer match', money(amounts.match / 12)) +
      row('Additional cash reserve needed', money(Math.max(0, amounts.target - settings.assets * E.startingAllocation(settings).cash / 100))))}
    ${card('Spending breakdown', buckets.length ? buckets.map(({label, value}) => `
      <div class="budget-bar"><div><span>${label}</span><strong>${money(value)}</strong></div>
      <progress value="${value}" max="${Math.max(1, amounts.spend)}" aria-label="${label} share of spending"></progress></div>`).join('')
      : '<p class="muted">Enter monthly spending to see the breakdown.</p>')}</div>` +
    card('Edit spending', fields(spendingFields) + field('goldFee','Annual IRA program fee',0,10000,1,'$'));
}

const forecastFields = [
  ['roi','Expected nominal return',-50,50,.1,'%'], ['optimistic','Optimistic return',-50,50,.1,'%'],
  ['volatility','Annual volatility',0,100,.1,'%'], ['inflation','Inflation',0,20,.1,'%'],
  ['cashReturn','Cash interest',0,30,.1,'%'], ['taxDrag','Brokerage tax drag',0,10,.1,'%']
];

function forecast() {
  const options = Object.entries(forecastViews).map(([key, view]) => [key, view.label]);
  const scenarioList = Object.keys(state.plans).filter(name => name !== state.active);
  if (!scenarioList.includes(compare)) compare = '';
  return heading('Forecast explorer', 'Inspect your simulated outcomes by year, or compare two saved scenarios.') +
    `<div class="forecast-tools">${scopeToggle()}<button type="button" data-go="career">Career scenarios</button></div><section class="card forecast-card">
      <div class="chart-controls">
        ${select('view','Metric',options,forecastView)}
        ${select('period','Years',[['full','Full forecast'],['first','First five years'],['last','Last five years']],timeframe)}
        ${select('dollars','Dollar basis',[['nominal','Nominal'],['real','Inflation-adjusted']],real ? 'real' : 'nominal')}
        ${scenarioList.length ? select('comparison','Compare scenario',[['','No comparison'],...scenarioList.map(name => [name,name])],compare) : ''}
      </div>
      <div id="forecast-view"></div>
    </section>` + card('Market assumptions', fields(forecastFields));
}

function forecastChart() {
  const all = projections();
  const periods = timeframe === 'first' ? all.slice(0,5) : timeframe === 'last' ? all.slice(-5) : all;
  const baseline = real ? all[0].year : undefined;
  const toSeries = definitions => definitions.map(([key,label,color,point]) =>
    chartSeries(periods, key, label, color, { baseline, point }));
  const get = (own, combined) => house ? combined : own;
  const view = forecastViews[forecastView];
  const showComparison = forecastView === 'wealth' || forecastView === 'accessible';
  if ($('comparison')) $('comparison').disabled = !showComparison;
  const series = {
    wealth: () => netWorthSeries(periods, get('individual','house'), { baseline, comparison: compare }),
    accessible: () => netWorthSeries(periods, get('accessible','houseAccessible'), { baseline, comparison: compare }),
    accounts: () => toSeries([
      [get('b','houseBroker'),'Brokerage','violet'], [get('r','houseRoth'),'Roth IRA','teal'],
      [get('k','houseWorkplace'),'401(k)','blue'], [get('h','houseCash'),'Cash','amber']
    ]),
    cashflow: () => toSeries([
      [get('g','houseIncome'),'Gross income','violet'], [get('ownExpense','expense'),'Expenses','amber'],
      [get('ownTax','tax'),'Estimated taxes','rose'], [get('ownSurplus','surplus'),'Surplus','teal']
    ]),
    investments: () => toSeries([
      [get('ownWorkplaceContribution','houseWorkplaceContribution'),'Employee 401(k)','violet'],
      [get('ownEmployerMatch','houseEmployerMatch'),'Employer match','blue'],
      [get('ira','houseIra'),'IRA contributions','teal'],
      [get('brokerage','houseBrokerageContribution'),'Brokerage contributions','amber']
    ]),
    roth: () => toSeries([
      ['magi','MAGI','violet'], ['lo','Phaseout starts','amber'], ['hi','Phaseout ends','rose']
    ]),
    rothAmounts: () => toSeries([
      [get('direct','houseDirect'),'Direct contributions','violet'],
      [get('backdoor','houseBackdoor'),'Backdoor contributions','teal'],
      ['eligible','Direct limit per person','amber']
    ]),
    debt: () => toSeries([
      [get('ownDebt','debt'),'Debt balance','rose'], [get('ownShortfall','shortfall'),'Annual shortfall','amber']
    ])
  }[forecastView]();
  const note = showComparison
    ? ' The darker band is P25–P75 (middle 50%). The lighter band is P10–P90 (middle 80%).'
    : forecastView === 'roth' ? ' Uses household income in years filed jointly.' : '';
  const noOverlap = compare && showComparison && series.at(-1).values.every(value => !value);
  $('forecast-view').innerHTML = `<h2>${view.title}</h2><p class="chart-note">${view.description}${note}</p>` +
    (noOverlap ? '<p class="chart-note">The comparison scenario has no data in this year range.</p>' : '') +
    '<div id="forecast-chart"></div>';
  return mountChart('forecast-chart', {
    title: view.title, periods, series,
    units: baseline ? `${baseline} USD` : 'nominal USD',
    download: data => download(`trajectory-${forecastView}.csv`, data, 'text/csv')
  });
}

function career() {
  const settings = plan();
  const last = projections().at(-1);
  const labels = [['Stay','base'],['Save more','save'],['Switch jobs','switch']];
  const key = house ? 'house' : 'individual';
  const outcomes = labels.map(([label, mode]) => {
    const result = projections(state.active, mode).at(-1)[key];
    return `<tr><th scope="row">${label}</th><td>${money(result[0])}</td><td>${money(result[2])}</td><td>${money(result[4])}</td><td>${money(result[2] - last[key][2])}</td></tr>`;
  }).join('');
  const switchOutside = settings.switchAge < settings.startAge || settings.switchAge > last.age;
  return heading('Career scenarios', 'Compare staying, reducing spending, or switching jobs with the same simulated market draws.') +
    `<div class="forecast-tools">${scopeToggle()}<button type="button" data-go="forecast">Back to Forecast</button></div>` +
    card('Median net worth by scenario', (switchOutside
      ? '<p class="chart-note">The selected job switch age falls outside this forecast.</p>' : '') +
      '<div id="career-chart"></div>') +
    card(`${last.year} scenario outcomes`, `<div class="table-scroll" tabindex="0" role="region" aria-label="Career outcome percentiles">
      <table><thead><tr><th scope="col">Scenario</th><th scope="col">P10</th><th scope="col">Median</th><th scope="col">P90</th><th scope="col">Median vs. stay</th></tr></thead><tbody>${outcomes}</tbody></table>
      </div><p class="chart-note">Switch results assume a successful job change. They do not estimate the likelihood of receiving an offer.</p>`) +
    card('Career assumptions', fields([
      ['raise','Annual raise',-15,25,.1,'%'], ['switchAge','Job switch age',18,110],
      ['switchRaise','Pay change at switch',-90,200,.1,'%'], ['switchCost','Switching cost',0,1000000,1,'$'],
      ['switchGap','Months without pay',0,12], ['extraSave','Extra monthly savings',0,100000,1,'$'],
      ['jobRisk','Annual job interruption chance',0,99,1,'%'], ['spouseRisk','Spouse interruption chance',0,99,1,'%']
    ]));
}

function settings() {
  const allocation = E.startingAllocation(plan());
  const scenarios = Object.keys(state.plans);
  return heading('Settings', 'Edit your plan assumptions, manage scenarios and back up your data.') +
    card('Saved scenarios', select('scenario','Active scenario',scenarios.map(name => [name,name]),state.active) +
      `<div class="actions"><button type="button" id="duplicate">Duplicate plan</button><button type="button" id="delete" ${scenarios.length < 2 ? 'disabled' : ''}>Delete plan</button></div>`) +
    card('Starting position', fields([
      ['startAge','Starting age',18,100], ['startYear','Starting year',1900,2200],
      ['startMonths','Months worked in starting year',0,12], ['salary','Annual gross salary',0,10000000,1,'$'],
      ['assets','Starting savings and investments',0,100000000,1,'$'],
      ['emergencyMonths','Emergency reserve months',0,24]
    ])) +
    card('Starting asset allocation', fields([
      ['cashShare','Cash',0,100-allocation.roth-allocation.workplace,.1,'%'],
      ['rothShare','Roth IRA',0,100-allocation.cash-allocation.workplace,.1,'%'],
      ['workplaceShare','401(k)',0,100-allocation.cash-allocation.roth,.1,'%']
    ]) + row('Brokerage (remaining)', Number(allocation.brokerage.toFixed(2)) + '%')) +
    card('Family and life events', '<p class="chart-note">Use age 0 for events you don’t want to model.</p>' + fields([
      ['marriage','Marriage age',0,110], ['spouseRatio','Spouse salary / your starting salary',0,500,.1,'%'],
      ['spouseAssets','Spouse assets at marriage',0,100000000,1,'$'],
      ['spouseContribution','Spouse 401(k) contribution',0,100,.1,'%'], ['spouseMatch','Spouse 401(k) match limit',0,100,.1,'%'],
      ['houseRent','Future household housing / month',0,100000,1,'$'], ['spouseOther','Other spouse costs / month',0,100000,1,'$'],
      ['firstChild','First child age',0,110], ['secondChild','Second child age',0,110],
      ['youngCost','Young child cost / month',0,100000,1,'$'], ['olderCost','Older child cost / month',0,100000,1,'$'],
      ['wedding','Wedding budget',0,1000000,1,'$'], ['health','Extra health & phone costs after age 26 / month',0,100000,1,'$']
    ]) + check('spouseGold','Spouse has paid IRA match program')) +
    card('Retirement and tax assumptions', check('backdoor','Model backdoor Roth when needed') +
      check('spouseBackdoor','Model spouse backdoor Roth') + fields([
      ['contribution','Traditional 401(k) contribution',0,100,.1,'%'],
      ['matchFull','Employer matches 100% up to',0,100,.1,'%'],
      ['matchHalf','Employer matches 50% on the next',0,100,.1,'%'],
      ['goldMatch','IRA program match',0,25,.1,'%'], ['iraLimit','Starting year IRA limit',0,30000,1,'$'],
      ['kLimit','Starting year 401(k) limit',0,100000,1,'$'],
      ['singleLower','Single Roth phaseout starts',0,5000000,1,'$'], ['singleUpper','Single Roth phaseout ends',0,5000000,1,'$'],
      ['jointLower','Joint Roth phaseout starts',0,5000000,1,'$'], ['jointUpper','Joint Roth phaseout ends',0,5000000,1,'$'],
      ['otherMagi','Other MAGI income (eligibility only)',0,10000000,1,'$'],
      ['limitGrowth','Annual tax limit growth',0,20,.1,'%'], ['stateTax','Approximate state income tax rate',0,20,.1,'%']
    ])) +
    card('Data and backups', `<div class="actions">
      <button type="button" id="backup">Export plans JSON</button><button type="button" id="sqlite">Export SQLite</button>
      <button type="button" id="csv">Export full forecast CSV</button><button type="button" id="restore">Import plans JSON</button>
      <button type="button" id="reset">Clear active plan assumptions</button>
    </div><input type="file" id="file" accept="application/json,.json" hidden>
    <p class="chart-note">Plans are stored in SQLite on this device. A JSON backup can restore or move plans. Importing replaces the saved plans.</p>
    <p id="offline" class="chart-note" role="status">${escape(offline)}</p>`);
}

function setup() {
  const year = new Date().getFullYear() + 1;
  const input = (key, label, options) => `<label class="setup-field">${label}<input name="${key}" type="number" ${options}></label>`;
  return `<section class="setup-page">
    ${heading('Start your plan', 'Use your age and savings to get started. Your plan stays on this device.')}
    <div class="card setup-card">
      <form id="setup">
        <div class="setup-fields">
          ${input('startAge','Your age in the first forecast year','min="18" max="100" step="1" inputmode="numeric" required')}
          ${input('assets','Starting savings and investments ($)','min="0" max="100000000" step="1" inputmode="numeric" placeholder="Optional"')}
        </div>
        <details class="plan-disclosure">
          <summary>Budget and timing options</summary>
          <div class="setup-fields">
            ${input('startYear','First forecast year',`min="1900" max="2200" step="1" value="${year}" inputmode="numeric" required`)}
            ${input('salary','Annual gross salary ($)','min="0" max="10000000" step="1" inputmode="numeric" placeholder="Optional"')}
            ${input('rent','Monthly housing cost ($)','min="0" max="100000" step="1" inputmode="numeric" placeholder="Optional"')}
            ${input('misc','Other monthly spending ($)','min="0" max="100000" step="1" inputmode="numeric" placeholder="Optional"')}
          </div>
        </details>
        <div class="actions">
          <button type="submit" class="primary">Start planning</button>
          <button type="button" id="restore">Import a JSON backup</button>
        </div>
        <input type="file" id="file" accept="application/json,.json" hidden>
      </form>
    </div>
  </section>`;
}

function go(next, focusHeading = false) {
  if (next === tab) return;
  tab = next;
  history.replaceState(null, '', '#' + next);
  render();
  if (focusHeading) {
    const title = $('screen').querySelector('h1');
    title.setAttribute('tabindex', '-1');
    title.focus({ preventScroll: true });
  }
  window.scrollTo(0, 0);
}

function render() {
  disposeCharts.forEach(dispose => dispose());
  disposeCharts = [];
  status();
  $('nav').hidden = !state;
  $('screen').classList.toggle('empty-screen', !state);
  if (!state) {
    $('screen').innerHTML = setup();
    $('setup').onsubmit = event => {
      event.preventDefault();
      const form = event.currentTarget;
      const entries = Object.fromEntries([...new FormData(form)].map(([key, value]) => [key, Number(value)]));
      const name = 'My plan';
      form.querySelector('button[type="submit"]').disabled = true;
      tab = 'plan';
      history.replaceState(null, '', '#plan');
      save(current => current || { active: name, plans: { [name]: {
        ...E.defaults, ...entries, switchAge: entries.startAge + 2
      } } });
    };
    bindImport();
    return;
  }

  $('nav').querySelectorAll('[data-tab]').forEach(button => {
    const active = button.dataset.tab === (tab === 'career' ? 'forecast' : tab);
    button.setAttribute('aria-current', active ? 'page' : 'false');
  });
  if (tab === 'plan') {
    const currentPlan = plan(), scenario = state.active;
    $('screen').innerHTML = heading('Retirement & goals', escape(scenario) + ' · ' + currentPlan.startYear + ' dollars') + '<div id="planner"></div>';
    disposeCharts.push(TrajectoryPlanner.mount($('planner'), currentPlan, E.plan(currentPlan), {
      save: revise => save(current => {
        const existing = existingPlan(current, scenario);
        existing.retirement = revise(TrajectoryRetirement.normalize(existing.retirement) ?? TrajectoryRetirement.normalize({}));
        return current;
      }),
      download,
      focusOutlook: () => { if (!storageError) $('outlook')?.focus(); }
    }));
  } else {
    $('screen').innerHTML = ({ overview, budget, forecast, career, settings })[tab]() +
      '<p class="foot">Illustrative projections from 1,500 seeded simulations. Taxes and retirement rules are simplified. Review assumptions before relying on results.</p>';
  }

  if (tab === 'overview') {
    const periods = projections();
    disposeCharts.push(mountChart('overview-chart', {
      title: 'Wealth trajectory', periods, series: netWorthSeries(periods, house ? 'house' : 'individual', {}),
      showTable: false
    }));
  }
  if (tab === 'forecast') {
    let dispose = forecastChart();
    disposeCharts.push(() => dispose());
    const refresh = () => {
      dispose();
      dispose = forecastChart();
    };
    $('view').onchange = event => { forecastView = event.target.value; refresh(); };
    $('period').onchange = event => { timeframe = event.target.value; refresh(); };
    $('dollars').onchange = event => { real = event.target.value === 'real'; refresh(); };
    if ($('comparison')) $('comparison').onchange = event => { compare = event.target.value; refresh(); };
  }
  if (tab === 'career') {
    const periods = projections();
    const key = house ? 'house' : 'individual';
    const series = [['base','Stay','violet'],['save','Save more','teal'],['switch','Switch jobs','amber']]
      .map(([mode, label, color]) => chartSeries(projections(state.active, mode), key, label, color));
    disposeCharts.push(mountChart('career-chart', {
      title: 'Median net worth by scenario', periods, series,
      download: data => download('trajectory-career.csv', data, 'text/csv')
    }));
  }
  bind();
}

function bindImport() {
  $('restore').onclick = () => $('file').click();
  $('file').onchange = async event => {
    const input = event.target;
    const file = input.files[0];
    input.value = '';
    if (!file) return;
    let imported;
    try {
      imported = TrajectoryStorage.normalize(JSON.parse(await file.text()));
    } catch {
      alert('Invalid Trajectory JSON backup.');
      return;
    }
    if (!state || confirm('Replace your saved plans with this backup?')) save(() => imported);
  };
}

function bind() {
  document.querySelectorAll('[data-go]').forEach(button => {
    button.onclick = () => go(button.dataset.go, true);
  });
  document.querySelectorAll('[data-scope]').forEach(button => {
    button.onclick = () => {
      house = button.dataset.scope === 'household';
      render();
      document.querySelector('[data-scope="' + button.dataset.scope + '"]').focus();
    };
  });

  const name = state.active;
  document.querySelectorAll('[data-field]').forEach(input => {
    input.onchange = () => {
      const key = input.dataset.field;
      if (input.type === 'number' && input.value === '') {
        input.value = plan()[key];
        return;
      }
      let value = input.type === 'checkbox' ? input.checked
        : Math.min(Number(input.max), Math.max(Number(input.min), input.valueAsNumber));
      if (typeof value === 'number') {
        if (!Number.isFinite(value)) return;
        if (['startAge','startYear','startMonths','switchAge','switchGap','marriage','firstChild','secondChild'].includes(key)) value = Math.round(value);
      }
      save(current => {
        existingPlan(current, name)[key] = value;
        return current;
      });
    };
  });

  if (tab !== 'settings') return;
  $('scenario').onchange = event => {
    const selected = event.target.value;
    save(current => {
      existingPlan(current, selected);
      current.active = selected;
      return current;
    });
  };
  $('duplicate').onclick = () => {
    const duplicate = prompt('Name for the new scenario', 'Alternative plan')?.trim();
    if (!duplicate) return;
    if (Object.hasOwn(state.plans, duplicate)) {
      alert('A scenario already has that name.');
      return;
    }
    save(current => {
      if (Object.hasOwn(current.plans, duplicate)) throw new Error('That scenario name is already in use.');
      current.plans[duplicate] = { ...existingPlan(current, name) };
      current.active = duplicate;
      return current;
    });
  };
  $('delete').onclick = () => {
    if (!confirm('Delete this scenario?')) return;
    save(current => {
      existingPlan(current, name);
      if (Object.keys(current.plans).length < 2) throw new Error('At least one scenario is required.');
      delete current.plans[name];
      if (current.active === name) current.active = Object.keys(current.plans)[0];
      return current;
    });
  };
  $('reset').onclick = () => {
    if (!confirm('Clear the financial assumptions in the active plan?')) return;
    save(current => {
      const existing = existingPlan(current, name);
      current.plans[name] = { ...E.defaults, startAge: existing.startAge,
        startYear: existing.startYear, switchAge: existing.startAge + 2 };
      return current;
    });
  };
  $('backup').onclick = () => download('trajectory-plans.json', JSON.stringify(state, null, 2), 'application/json');
  $('sqlite').onclick = async () => {
    try {
      await queue;
      download('trajectory.sqlite3', await database.exportFile(), 'application/vnd.sqlite3');
    } catch (error) {
      alert('The SQLite file could not be exported.');
      console.error(error);
    }
  };
  $('csv').onclick = downloadForecast;
  bindImport();
}

function setOffline(message) {
  offline = message;
  if ($('offline')) $('offline').textContent = message;
}

async function enableOffline() {
  if (!('serviceWorker' in navigator)) {
    setOffline('Offline access is unavailable in this browser.');
    return;
  }
  try {
    const registration = await navigator.serviceWorker.register('./sw.js');
    const worker = registration.installing;
    worker?.addEventListener('statechange', () => {
      if (worker.state === 'redundant' && !registration.active) setOffline('Reload while online to retry offline setup.');
    });
    await navigator.serviceWorker.ready;
    setOffline('Ready to open offline.');
  } catch (error) {
    setOffline('Reload while online to retry offline setup.');
    console.error(error);
  }
}

async function shareApp() {
  const url = new URL('./', location.href).href;
  try {
    if (navigator.share) await navigator.share({ title: 'Trajectory', url });
    else {
      await navigator.clipboard.writeText(url);
      $('share').textContent = 'Link copied';
      setTimeout(() => { $('share').textContent = 'Share app'; }, 2200);
    }
  } catch (error) {
    if (error.name !== 'AbortError') prompt('Copy this app link', url);
  }
}

async function start() {
  $('nav').innerHTML = tabs.map(([label,key]) => `<button type="button" data-tab="${key}">${svgIcon(key)}<span>${label}</span></button>`).join('');
  $('nav').querySelectorAll('[data-tab]').forEach(button => {
    button.onclick = () => go(button.dataset.tab);
  });
  window.addEventListener('hashchange', () => {
    tab = route();
    if (state) render();
  });
  $('share').onclick = shareApp;
  enableOffline();
  try {
    database = await TrajectoryStorage.open();
    state = database.state;
    render();
  } catch (error) {
    $('storage').textContent = 'The local SQLite database could not be opened.';
    $('screen').innerHTML = '<div class="card"><p>Allow browser storage for this site and reload to retry.</p><button id="retry">Reload Trajectory</button></div>';
    $('retry').onclick = () => location.reload();
    console.error(error);
  }
}

start();
})();
