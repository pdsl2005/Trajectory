'use strict';

const TrajectoryPlanner = (() => {
  const R = TrajectoryRetirement;
  const Chart = TrajectoryCharts;
  const { escape, money } = Chart;
  const percent = new Intl.NumberFormat('en-US', { style: 'percent', maximumFractionDigits: 1 });
  const number = new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 });
  const byId = (host, id) => host.querySelector('#' + id);
  const field = (name, label, value, { min = 0, max = 1000000, step = 1, required = false, hint = '', placeholder = '' } = {}) => `
    <div class="setup-field">
      <label for="plan-${name}">${label}</label>
      <input id="plan-${name}" type="number" name="${name}" min="${min}" max="${max}" step="${step}"
        inputmode="${step < 1 ? 'decimal' : 'numeric'}" value="${value ?? ''}" placeholder="${escape(placeholder)}"
        ${required ? 'required' : ''} ${hint ? `aria-describedby="plan-hint-${name}"` : ''}>
      ${hint ? `<small id="plan-hint-${name}">${hint}</small>` : ''}
    </div>`;
  const metric = (label, value, note) => `<div class="metric"><p>${label}</p><strong>${value}</strong><small>${note}</small></div>`;
  const calendarYear = (assumptions, age) => assumptions.startYear + age - assumptions.startAge;

  function inputs(s, stored, budget) {
    const age = { min: s.startAge, max: R.maxAge };
    const rate = { min: -30, max: 25, step: .1 };
    const volatility = { max: 60, step: .1 };
    return `<form id="retirement-form">
      <div class="plan-fields">
        ${field('retireAge', 'Retirement age', s.retireAge, { ...age, required: true })}
        ${field('monthlySpend', 'Spending in retirement ($/mo)', stored.monthlySpend, {
          required: true, placeholder: budget.spend > 0 ? number.format(budget.spend) : 'Enter your estimate'
        })}
        ${field('monthlySave', 'Saving until retirement ($/mo)', stored.monthlySave, {
          placeholder: String(s.budgetSave), hint: `Blank uses your modeled budget estimate of ${money(s.budgetSave)}/mo, including payroll contributions and match.`
        })}
      </div>
      <details class="plan-disclosure">
        <summary>Advanced settings</summary>
        <div class="plan-fields">
          ${field('startingAssets', 'Starting assets override ($)', stored.startingAssets, {
            max: 100000000, placeholder: number.format(s.assets), hint: 'Blank uses starting assets from this scenario.'
          })}
          ${field('throughAge', 'Plan through age', stored.throughAge === null ? null : s.throughAge, { ...age, placeholder: String(s.throughAge) })}
          ${field('monthlyIncome', 'Net retirement income ($/mo)', stored.monthlyIncome || null, {
            hint: 'Enter after-tax income such as Social Security or a pension.'
          })}
          ${field('incomeAge', 'Income starts at age', stored.incomeAge, { min: 18, max: R.maxAge, placeholder: String(s.incomeAge), hint: 'Applied during retirement.' })}
          ${field('beforeReturn', 'Return before retirement (%)', stored.beforeReturn, {
            ...rate, placeholder: number.format(s.beforeReturn)
          })}
          ${field('afterReturn', 'Return in retirement (%)', stored.afterReturn, {
            ...rate, placeholder: number.format(s.afterReturn)
          })}
          ${field('beforeVolatility', 'Volatility before retirement (%)', stored.beforeVolatility, {
            ...volatility, placeholder: number.format(s.beforeVolatility)
          })}
          ${field('afterVolatility', 'Volatility in retirement (%)', stored.afterVolatility, {
            ...volatility, placeholder: number.format(s.afterVolatility)
          })}
          ${field('inflation', 'Inflation (%)', stored.inflation, { max: 15, step: .1, placeholder: number.format(s.inflation) })}
        </div>
        <p class="chart-note">Blank return and volatility fields use your forecast assumptions before retirement and carry them into retirement. Returns are entered before inflation.</p>
        <p class="chart-note"><a href="https://www.ssa.gov/prepare/get-benefits-estimate" target="_blank" rel="noopener noreferrer">Get a Social Security estimate</a></p>
      </details>
      <div class="actions"><button type="submit" class="primary">${stored.monthlySpend === null ? 'Build retirement forecast' : 'Update retirement forecast'}</button></div>
    </form>`;
  }

  function expenseForm(item, startAge) {
    return `<form class="expense-form" data-id="${item?.id ?? ''}">
      <div class="expense-fields">
        <label class="setup-field">Expense name
          <input type="text" name="name" required maxlength="60" value="${escape(item?.name ?? '')}" placeholder="e.g. Home down payment">
        </label>
        <label class="setup-field">Cost per year ($)
          <input type="number" name="cost" required min="1" max="100000000" step="1" inputmode="numeric" value="${item?.cost ?? ''}">
        </label>
        <label class="setup-field">Age when due
          <input type="number" name="startAge" required min="18" max="${R.maxAge}" step="1" inputmode="numeric"
            value="${item?.startAge ?? ''}" placeholder="${startAge}">
        </label>
      </div>
      <details class="plan-disclosure" ${item && item.endAge > item.startAge ? 'open' : ''}>
        <summary>Repeat annually</summary>
        <label class="setup-field expense-end">Last age to pay
          <input type="number" name="endAge" min="18" max="${R.maxAge}" step="1" inputmode="numeric"
            value="${item && item.endAge > item.startAge ? item.endAge : ''}">
          <small>Leave blank for a one-time expense.</small>
        </label>
      </details>
      <div class="actions">
        <button type="submit" class="primary">${item ? 'Save expense' : 'Add expense'}</button>
        ${item ? '<button type="button" data-remove>Remove expense</button>' : ''}
      </div>
    </form>`;
  }

  function expenses(s, result) {
    const entries = s.expenses.map((expense, index) => {
      const firstYear = calendarYear(s, expense.startAge), lastYear = calendarYear(s, expense.endAge);
      const timing = firstYear === lastYear ? `${firstYear} · age ${expense.startAge}` : `${firstYear}–${lastYear} · annual`;
      const bounds = expense.startAge < s.startAge || expense.endAge > s.throughAge;
      const coverage = result.expenseFunding[index];
      const status = coverage === null ? 'Outside the forecast'
        : `${percent.format(coverage)} fully funded${bounds ? ' for years in this forecast' : ''}`;
      return `<details class="expense-entry">
        <summary><span class="expense-description"><strong>${escape(expense.name)}</strong><small>${timing} · ${status}</small></span>
          <strong>${money(expense.cost)}${firstYear === lastYear ? '' : '/yr'}</strong></summary>
        ${expenseForm(expense, s.startAge)}
      </details>`;
    }).join('');
    return `<section class="card">
      <h2>Major expenses</h2>
      <p class="chart-note">Schedule a home down payment, tuition, or any large expense in ${s.startYear} dollars.</p>
      ${entries}
      ${s.expenses.length < R.maxExpenses ? `<details class="add-expense plan-disclosure"><summary>Add an expense</summary>
        ${expenseForm(null, s.startAge)}</details>` : '<p class="muted">This scenario has reached its expense limit.</p>'}
    </section>`;
  }

  function summary(s, result) {
    if (!result.hasRetirement) {
      return s.expenses.length
        ? '<p class="plan-note">This expense preview includes your savings and scheduled costs. Add retirement spending to include living costs after retirement.</p>' : '';
    }
    const first = result.periods[s.retireAge - s.startAge];
    const linkedExpenses = result.periods.some(period => period.expenseCost > 0);
    const coverageDetail = `Through age ${s.throughAge}` + (linkedExpenses
      ? ` · ${percent.format(result.baselineCoverage)} funded without major expenses`
      : ` · ${calendarYear(s, s.throughAge)}`);
    return `<section class="card plan-summary" aria-labelledby="outlook">
      <div class="plan-summary-head">
        <div><h2 id="outlook" tabindex="-1">Plan outlook</h2><p>Retire at ${s.retireAge} in ${calendarYear(s, s.retireAge)} · ${s.startYear} dollars</p></div>
        <div class="coverage"><strong>${percent.format(result.coverage)}</strong><span>of simulations cover all planned spending</span></div>
      </div>
      <p class="coverage-note">${coverageDetail}</p>
      <div class="plan-metrics">
        ${metric('At retirement', money(result.retirementStart[2]), 'Median balance at the start of retirement')}
        ${metric('From savings when retirement starts', money(Math.max(0, first.spend - first.income) / 12) + '/mo', 'Spending less income, before major expenses')}
        ${metric(`Remaining at age ${s.throughAge}`, money(result.periods.at(-1).balance[2]), 'Median end-of-year balance')}
      </div>
    </section>`;
  }

  function forecastPanel(s, result) {
    if (!result.hasRetirement && !s.expenses.length) return '';
    const title = result.hasRetirement ? 'Retirement balance' : 'Balance with major expenses';
    return `<details class="card plan-panel" id="retirement-forecast">
      <summary>Explore the year-by-year forecast</summary>
      <p class="chart-note">${title} from age ${s.startAge} to ${s.throughAge}. Shading shows the middle 50% and 80% of simulated balances.</p>
      <div id="retirement-chart"></div>
    </details>`;
  }

  function planNotes(s, result) {
    return `<details class="card plan-panel">
      <summary>How the projection works</summary>
      <p>Uses one pool of ${money(s.assets)} and ${number.format(result.runs)} seeded investment simulations. The plan starts in ${s.startYear} at age ${s.startAge}. Full-year saving ends when retirement begins. Enter income and costs in ${s.startYear} purchasing power.</p>
      <p>Each year applies investment returns first, then income, living costs and scheduled expenses. Expenses due together share the available balance. A simulation counts as fully funded when it covers every modeled payment through age ${s.throughAge}.</p>
      <p>Balance reflects invested assets only. Taxes, account access rules, debt and changes to benefits are outside this model. Include taxes and health care in spending and enter net retirement income.</p>
    </details>`;
  }

  function values(form) {
    return Object.fromEntries([...new FormData(form)].map(([name, value]) => [name, value === '' ? null : Number(value)]));
  }

  function ensureOrder(first, last, message) {
    last.setCustomValidity(last.value && Number(last.value) < Number(first.value) ? message : '');
    return last.reportValidity();
  }

  function mount(host, plan, budget, { save, download, focusOutlook }) {
    const stored = R.normalize(plan.retirement) ?? R.normalize({});
    const s = R.settings(plan, budget);
    const result = s.monthlySpend !== null || s.expenses.length ? R.project(s) : { hasRetirement: false, runs: R.trials };
    const hasRetirement = result.hasRetirement;
    const editor = inputs(s, stored, budget);
    host.innerHTML = `
      ${summary(s, result)}
      ${hasRetirement ? `<details class="card plan-panel"><summary>Retirement assumptions</summary>${editor}</details>`
        : `<section class="card"><h2>Retirement</h2><p class="chart-note">Starts with ${money(s.assets)} at age ${s.startAge} in ${s.startYear}.</p>${editor}</section>`}
      ${expenses(s, result)}
      ${forecastPanel(s, result)}
      ${planNotes(s, result)}
    `;

    const form = byId(host, 'retirement-form');
    form.oninput = () => form.elements.throughAge.setCustomValidity('');
    form.onsubmit = event => {
      event.preventDefault();
      if (!ensureOrder(form.elements.retireAge, form.elements.throughAge, 'Enter an age at or after retirement.')) return;
      form.querySelector('button[type="submit"]').disabled = true;
      const changes = values(form);
      save(current => ({ ...current, ...changes })).then(focusOutlook);
    };

    host.querySelectorAll('.expense-form').forEach(editor => {
      const id = editor.dataset.id;
      editor.oninput = () => editor.elements.endAge.setCustomValidity('');
      editor.onsubmit = event => {
        event.preventDefault();
        const label = editor.elements.namedItem('name');
        const name = label.value.trim();
        if (!name) {
          label.setCustomValidity('Enter an expense name.');
          label.reportValidity();
          label.oninput = () => label.setCustomValidity('');
          return;
        }
        if (!ensureOrder(editor.elements.startAge, editor.elements.endAge, 'Enter an age at or after the first payment.')) return;
        editor.querySelector('button[type="submit"]').disabled = true;
        const { cost, startAge, endAge } = values(editor);
        const expense = { id: id || crypto.randomUUID(), name, cost, startAge, endAge: endAge ?? startAge };
        save(current => {
          if (!id && current.expenses.length >= R.maxExpenses) throw new Error('Expense limit reached.');
          if (id && !current.expenses.some(item => item.id === id)) throw new Error('This expense no longer exists.');
          return { ...current, expenses: id
            ? current.expenses.map(item => item.id === id ? expense : item)
            : [...current.expenses, expense] };
        });
      };
      const remove = editor.querySelector('[data-remove]');
      if (remove) remove.onclick = () => {
        const name = editor.elements.namedItem('name').defaultValue;
        if (confirm(`Remove “${name}” from this scenario?`)) {
          save(current => ({ ...current, expenses: current.expenses.filter(item => item.id !== id) }));
        }
      };
    });

    const details = byId(host, 'retirement-forecast');
    let dispose;
    if (details) details.ontoggle = () => {
      if (!details.open || dispose) return;
      const periods = result.periods;
      const series = [{ label: 'Median balance', color: 'violet', band: true, values: periods.map(period => period.balance) }];
      if (periods.some(period => period.expenseCost > 0)) {
        series.push({ label: 'Without major expenses', color: 'teal', dash: '7 4', values: periods.map(period => period.noExpenses) });
      }
      dispose = Chart.mount(byId(host, 'retirement-chart'), {
        title: 'Portfolio balance', periods, series, units: `${s.startYear} USD`,
        initialIndex: hasRetirement ? s.retireAge - s.startAge : periods.findIndex(period => period.expenseCost > 0),
        annotation: period => [
          [period.age === s.retireAge ? 'Retirement begins' : '', ''],
          ['Saving', money(period.save)], ['Retirement income', money(period.income)],
          ['Retirement spending', money(period.spend)],
          [period.goalNames.length === 1 ? period.goalNames[0] : 'Major expenses', money(period.expenseCost)], ['Share with a shortfall', percent.format(period.shortfall)]
        ].filter(([label, value]) => label && value !== '$0'),
        download: () => download('trajectory-retirement.csv', R.csv(periods), 'text/csv')
      });
    };
    return () => dispose?.();
  }

  return { mount };
})();
