'use strict';

const TrajectoryRetirement = (() => {
  const maxAge = 120;
  const maxExpenses = 40;
  const trials = 1000;
  const quantiles = [.1, .25, .5, .75, .9];

  function bounded(value, min, max, fallback = null) {
    return typeof value === 'number' && Number.isFinite(value)
      ? Math.max(min, Math.min(max, value)) : fallback;
  }

  function age(value) {
    const normalized = bounded(value, 18, maxAge);
    return normalized === null ? null : Math.round(normalized);
  }

  function normalize(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    const expenses = [];
    const ids = new Set();
    const incoming = Array.isArray(value.expenses) ? value.expenses.slice(0, maxExpenses) : [];
    for (const expense of incoming) {
      const name = typeof expense?.name === 'string' ? expense.name.trim().slice(0, 60) : '';
      const cost = bounded(expense?.cost, 0, 100000000, 0);
      const startAge = age(expense?.startAge);
      if (!name || !cost || !startAge) continue;
      let id = typeof expense.id === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(expense.id) ? expense.id : '';
      let suffix = expenses.length;
      while (!id || ids.has(id)) id = 'expense-' + suffix++;
      ids.add(id);
      expenses.push({ id, name, cost, startAge, endAge: Math.max(startAge, age(expense.endAge) ?? startAge) });
    }

    return {
      startingAssets: bounded(value.startingAssets, 0, 100000000),
      retireAge: age(value.retireAge),
      throughAge: age(value.throughAge),
      monthlySpend: bounded(value.monthlySpend, 0, 1000000),
      monthlySave: bounded(value.monthlySave, 0, 1000000),
      monthlyIncome: bounded(value.monthlyIncome, 0, 1000000, 0),
      incomeAge: age(value.incomeAge),
      beforeReturn: bounded(value.beforeReturn, -30, 25),
      beforeVolatility: bounded(value.beforeVolatility, 0, 60),
      afterReturn: bounded(value.afterReturn, -30, 25),
      afterVolatility: bounded(value.afterVolatility, 0, 60),
      inflation: bounded(value.inflation, 0, 15),
      expenses
    };
  }

  function settings(plan, { net, spend, c, match }) {
    const saved = normalize(plan.retirement) ?? normalize({});
    const budgetSave = Math.round(Math.max(0, net - spend) + (c + match) / 12);
    const retireAge = Math.max(plan.startAge, saved.retireAge ?? 65);
    const beforeReturn = saved.beforeReturn ?? bounded(plan.roi, -30, 25, 7);
    const beforeVolatility = saved.beforeVolatility ?? bounded(plan.volatility, 0, 60, 16);
    return {
      ...saved, startAge: plan.startAge, startYear: plan.startYear, assets: saved.startingAssets ?? bounded(plan.assets, 0, 100000000, 0),
      retireAge,
      throughAge: Math.max(retireAge, saved.throughAge ?? 95),
      incomeAge: saved.incomeAge ?? retireAge,
      monthlySave: saved.monthlySave ?? budgetSave,
      beforeReturn, beforeVolatility,
      afterReturn: saved.afterReturn ?? beforeReturn,
      afterVolatility: saved.afterVolatility ?? beforeVolatility,
      inflation: saved.inflation ?? bounded(plan.inflation, 0, 15, 2.5),
      budgetSave
    };
  }

  function random(seed) {
    let current = seed >>> 0;
    const next = () => {
      current = (Math.imul(current, 1664525) + 1013904223) >>> 0;
      return (current + .5) / 4294967296;
    };
    return () => Math.sqrt(-2 * Math.log(next())) * Math.cos(2 * Math.PI * next());
  }

  function percentiles(values) {
    values.sort((a, b) => a - b);
    return quantiles.map(q => values[Math.floor((values.length - 1) * q)]);
  }

  function project(s, { count = trials, seed = 91520 } = {}) {
    const hasRetirement = s.monthlySpend !== null;
    const years = Array.from({ length: s.throughAge - s.startAge + 1 }, (_, index) => {
      const age = s.startAge + index;
      const retired = age >= s.retireAge;
      const goals = s.expenses.map((expense, id) => ({ ...expense, index: id }))
        .filter(expense => age >= expense.startAge && age <= expense.endAge);
      return {
        age, year: s.startYear + index,
        save: retired ? 0 : s.monthlySave * 12,
        spend: retired && hasRetirement ? s.monthlySpend * 12 : 0,
        income: retired && age >= s.incomeAge ? s.monthlyIncome * 12 : 0,
        goals,
        expenseCost: goals.reduce((sum, expense) => sum + expense.cost, 0),
        mean: retired ? s.afterReturn : s.beforeReturn,
        volatility: retired ? s.afterVolatility : s.beforeVolatility,
        balances: [], baseline: [], misses: 0
      };
    });
    const draw = random(seed);
    const inflation = 1 + s.inflation / 100;
    const startBalances = [];
    const funded = new Array(s.expenses.length).fill(0);
    let successful = 0;
    let baselineSuccessful = 0;

    for (let run = 0; run < count; run++) {
      let balance = s.assets, noExpenses = s.assets;
      let shortfall = false, baselineShortfall = false;
      const missedExpenses = new Set();

      for (const year of years) {
        if (year.age === s.retireAge) startBalances.push(balance);
        const nominal = Math.max(-.95, Math.min(1.5, (year.mean + draw() * year.volatility) / 100));
        const growth = (1 + nominal) / inflation;
        const cashFlow = year.save + year.income - year.spend;
        const beforeExpenses = balance * growth + cashFlow;
        const baselineEnd = noExpenses * growth + cashFlow;
        const goalCoverage = year.expenseCost
          ? Math.max(0, Math.min(1, beforeExpenses / year.expenseCost)) : 1;
        // Expenses due in the same year share the money available after living costs.
        if (goalCoverage < 1 - 1e-10) {
          for (const expense of year.goals) missedExpenses.add(expense.index);
        }
        const end = beforeExpenses - year.expenseCost;
        if (end < -1e-7) {
          shortfall = true;
          year.misses++;
        }
        if (baselineEnd < -1e-7) baselineShortfall = true;
        balance = Math.max(0, end);
        noExpenses = Math.max(0, baselineEnd);
        year.balances.push(balance);
        year.baseline.push(noExpenses);
      }
      if (!shortfall) successful++;
      if (!baselineShortfall) baselineSuccessful++;
      for (let index = 0; index < funded.length; index++) {
        if (!missedExpenses.has(index)) funded[index]++;
      }
    }
    const periods = years.map(({ age, year, save, spend, income, expenseCost, goals, balances, baseline, misses }) => ({
      age, year, save, spend, income, expenseCost, goalNames: goals.map(expense => expense.name),
      balance: percentiles(balances), noExpenses: percentiles(baseline), shortfall: misses / count
    }));
    const expenseFunding = s.expenses.map((expense, index) => {
      const overlappingYears = Math.max(0, Math.min(expense.endAge, s.throughAge) - Math.max(expense.startAge, s.startAge) + 1);
      return overlappingYears ? funded[index] / count : null;
    });
    return {
      periods, expenseFunding, hasRetirement,
      coverage: successful / count,
      baselineCoverage: baselineSuccessful / count,
      retirementStart: percentiles(startBalances),
      runs: count
    };
  }

  function csv(periods) {
    const header = ['Year', 'Age', 'Annual saving', 'Retirement income', 'Retirement spending',
      'Major expenses', 'Shortfall share', 'Balance P10', 'Balance P25', 'Balance median',
      'Balance P75', 'Balance P90', 'Median without major expenses'];
    const rows = periods.map(p => [p.year, p.age, Math.round(p.save), Math.round(p.income), Math.round(p.spend),
      Math.round(p.expenseCost), p.shortfall, ...p.balance.map(Math.round), Math.round(p.noExpenses[2])]);
    return [header, ...rows].map(row => row.join(',')).join('\n');
  }

  return { maxAge, maxExpenses, trials, normalize, settings, project, csv };
})();

if (typeof module !== 'undefined') module.exports = TrajectoryRetirement;
