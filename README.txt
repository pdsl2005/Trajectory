TRAJECTORY

Trajectory is a buildless budgeting and forecasting PWA. The Share app button
shares the app URL. Each new browser or installation starts with a blank setup
form, or can import a Trajectory JSON backup. The link carries no plan data.

On iPhone, open the site in Safari, use Share > Add to Home Screen, turn on
Open as Web App, and tap Add. Launch online once to prepare it for offline use.

The browser runs SQLite through the bundled sql.js WebAssembly build. SQLite
is saved in IndexedDB at the end of each successful edit. All plan data and
simulations stay in the browser. The host serves app files. Browser storage
is specific to the browser or installed app and can be cleared. Export a JSON
backup to transfer or recover plans. SQLite and forecast CSV exports are also
available under Settings. Previous localStorage plans are migrated if they are
visible in the same origin and browser context.

The forecast explorer has individual and household views, a year scrubber,
nominal and inflation-adjusted figures, selectable series, net-worth
percentile bands, a saved-scenario overlay and annual data downloads. Household
account totals are calculated on each simulated path before taking percentiles.

Development: serve dist/ on localhost. Run node test.js to check the model and
chart calculations. No build is required.

The Plan tab projects retirement and major expenses using a separate, real-
dollar cash-flow model. Enter age, monthly retirement spending, and optional
monthly savings. Advanced settings control the planning horizon, asset balance,
income start age, inflation and returns. Major expenses can be one-time or
annual over a range of ages. The expanded forecast compares the same simulated
market paths with and without major expenses and exports annual cash flows and
balance percentiles. All assumptions are saved per scenario alongside the
existing budget and forecast data.

Native iPhone app and card backend setup are documented in NATIVE.md.
