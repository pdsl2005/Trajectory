const assert = require('node:assert/strict');
const E = require('./dist/engine.js');
const Chart = require('./dist/charts.js');

assert.equal(E.defaults.salary, 0);
assert.equal(E.defaults.assets, 0);
assert.equal(E.defaults.rent, 0);

const plan = {
  ...E.defaults, ...E.previousRules, salary: 80000, assets: 18000,
  contribution: 5, rent: 1100, misc: 900, startAge: 28, startYear: 2030,
  marriage: 31, spouseRatio: 95, houseRent: 2100, switchAge: 30,
  jobRisk: 0, spouseRisk: 0
};
const budget = E.plan(plan);
assert.equal(budget.match, 3200);
assert.equal(budget.allow, 7500);
assert.equal(E.allowance(173000,158000,173000,7500),0);
assert.equal(E.allowance(165500,158000,173000,7500),3750);
assert.ok(Math.abs(budget.g / 12 - budget.c / 12 - budget.tax / 12 - budget.spend - budget.ira / 12 - budget.broker) < 1e-8);
assert.deepEqual(E.startingAllocation(plan), { cash: 25, roth: 25, workplace: 5, brokerage: 45 });

const rows = E.simulate(plan, { n: 200 });
assert.deepEqual(rows, E.simulate(plan, { n: 200 }));
assert.equal(rows.length, E.forecastYears);
assert.deepEqual([rows[0].year, rows[0].age, rows.at(-1).year, rows.at(-1).age], [2030, 28, 2040, 38]);
for (const record of rows) {
  for (const values of Object.values(record).filter(Array.isArray)) {
    assert.ok(values.every(Number.isFinite));
    assert.ok(values.every((value, i) => i === 0 || value >= values[i - 1]));
  }
}
assert.equal(rows[0].houseIncome[2], rows[0].g[2]);
assert.ok(rows.at(-1).houseIncome[2] > rows.at(-1).g[2]);
const baseline = E.simulate(plan, { n: 1, det: true });
const switched = E.simulate(plan, { n: 1, det: true, mode: 'switch' });
assert.ok(switched.at(-1).individual[2] > baseline.at(-1).individual[2]);
const married = baseline.at(-1);
assert.equal(married.houseIncome[2], married.g[2] + married.p[2]);
assert.ok(Math.abs(married.house[2] - (married.houseCash[2] + married.houseRoth[2] + married.houseWorkplace[2] + married.houseBroker[2] - married.debt[2])) < 1e-7);

const domain = Chart.axis([-420000, -1200, 1530000]);
assert.ok(domain.min <= -420000 && domain.max >= 1530000);
assert.ok(domain.ticks.includes(0));
assert.ok(Chart.axis([]).max > 0);
assert.equal(Chart.linePath([1, undefined, 3, 4], i => i, y => y), 'M0,1  M2,3 L3,4');
const median = { label: 'Median', values: [[-100, 0, 250, 550, 1000]], band: true };
assert.equal(Chart.csvText([{ year: 2030, age: 28 }], [median], median),
  '"Year","Age","Median","P10","P25","P75","P90"\n2030,28,250,-100,0,550,1000');
console.log('Model and chart calculation tests passed.');

const R = require('./dist/retirement.js');
const retirementBase = {
  ...plan, startAge: 60, startYear: 2030, assets: 18000,
  retirement: {
    retireAge: 61, throughAge: 64, monthlySave: 500, monthlySpend: 1000,
    monthlyIncome: 1000, incomeAge: 63,
    beforeReturn: 0, beforeVolatility: 0, afterReturn: 0, afterVolatility: 0, inflation: 0,
    expenses: [
      { id: 'tuition', name: 'Tuition', cost: 2000, startAge: 61, endAge: 62 },
      { id: 'travel', name: 'Travel', cost: 500, startAge: 64 },
      { id: 'later', name: 'Later cost', cost: 500, startAge: 65 }
    ]
  }
};
const retirement = R.settings(retirementBase, budget);
const projection = R.project(retirement, { count: 30 });
assert.equal(projection.retirementStart[2], 24000);
assert.deepEqual(projection.periods.map(p => p.balance[2]), [24000, 10000, 0, 0, 0]);
assert.deepEqual(projection.periods.map(p => p.noExpenses[2]), [24000, 12000, 0, 0, 0]);
assert.deepEqual(projection.periods.map(p => p.shortfall), [0, 0, 1, 0, 1]);
assert.deepEqual(projection.expenseFunding, [0, 0, null]);
assert.equal(projection.coverage, 0);
assert.equal(projection.baselineCoverage, 1);
assert.equal(projection.periods[3].income, 12000);
assert.equal(projection.periods[4].year, 2034);
assert.match(R.csv(projection.periods), /2032,62,0,0,12000,2000,1,/);

const expenseOnly = R.project({ ...retirement, monthlySpend: null }, { count: 10 });
assert.equal(expenseOnly.hasRetirement, false);
assert.deepEqual(expenseOnly.expenseFunding, [1, 1, null]);
const alreadyRetired = R.settings({ ...retirementBase, startAge: 75,
  retirement: { ...retirementBase.retirement, monthlySpend: 0, startingAssets: 777 } }, budget);
assert.equal(alreadyRetired.retireAge, 75);
assert.equal(R.project(alreadyRetired, { count: 1 }).retirementStart[2], 777);

const inflationCase = R.project({ ...retirement, startAge: 60, retireAge: 60, throughAge: 60,
  assets: 1000, monthlySpend: 0, expenses: [], afterReturn: 5, inflation: 5 }, { count: 1 });
assert.equal(inflationCase.periods[0].balance[2], 1000);
const withRisk = { ...retirement, afterReturn: 5, afterVolatility: 12 };
assert.deepEqual(R.project(withRisk, { count: 30 }), R.project(withRisk, { count: 30 }));
assert.equal(R.normalize({ monthlySpend: -1, expenses: [
  {id:'same', name:'One', cost:123, startAge:27},
  {id:'same', name:'Two', cost:456, startAge:28}
]}).expenses[1].id, 'expense-1');
console.log('Retirement and expense projection tests passed.');
