const fs = require('node:fs');
const path = require('node:path');
const engine = require('../../dist/engine');
const retirement = require('../../dist/retirement');

const plan = {
  ...engine.defaults,
  salary: 132000, startAge: 30, startMonths: 7, assets: 93000,
  cashShare: 23, rothShare: 28, workplaceShare: 29,
  rent: 2100, food: 450, utilities: 200, goods: 320,
  contribution: 8, matchFull: 4, matchHalf: 2, stateTax: 5,
  marriage: 33, spouseRatio: 80, spouseContribution: 6, spouseMatch: 4,
  spouseAssets: 50000, houseRent: 2800, spouseOther: 220, wedding: 28000,
  firstChild: 35, secondChild: 38, youngCost: 1200, olderCost: 600,
  switchAge: 33, switchGap: 2, switchCost: 5000, goldFee: 120, goldMatch: 3,
  retirement: retirement.normalize({
    retireAge: 45, throughAge: 58, monthlySpend: 5400, monthlyIncome: 1350, incomeAge: 48,
    expenses: [{ id: 'roof', name: 'Roof', cost: 17000, startAge: 41, endAge: 42 }]
  })
};

const runs = [
  { n: 1, det: true },
  { n: 128, mode: 'switch' },
  { n: 128, mode: 'save' },
  { n: 1, det: true, returnOverride: plan.optimistic }
];
const budget = engine.plan(plan);
const fixture = {
  backup: { active: 'Fixture', plans: { Fixture: plan } },
  budget,
  forecasts: runs.map(options => ({ options, output: engine.simulate(plan, options) })),
  retirement: retirement.project(retirement.settings(plan, budget), { count: 100, seed: plan.seed })
};

const file = path.join(__dirname, 'TrajectoryCoreTests/Fixtures/models.json');
fs.writeFileSync(file, JSON.stringify(fixture));
