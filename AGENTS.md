# Repository Guidelines

## Project Structure & Module Organization

Trajectory is a buildless budgeting and forecasting progressive web app. Edit the source directly in `dist/`, which is also the directory served to browsers. `index.html` loads the app, `style.css` defines its styles, and `app.js` manages the main interface. `engine.js` handles budgets and forecasts, `retirement.js` models retirement and major expenses, `planner.js` renders the Plan tab, and `charts.js` handles chart calculations and rendering. `storage.js` persists plans using the bundled sql.js files in `dist/vendor/` and IndexedDB. The service worker, web manifest, and icons also live in `dist/`. The test script is `test.js` at the repository root.

## Build, Test, and Development Commands

- Run `python3 -m http.server 8000 --directory dist` from the repository root and open `http://localhost:8000` to develop locally. The app runs directly from the served files.
- Run `node test.js` to check the budget and forecast models, chart calculations, and retirement and expense projections.

## Coding Style & Naming Conventions

Follow the surrounding code. Use two-space indentation within JavaScript blocks, single quotes for string literals, and camelCase for functions and variables. Keep financial calculations in the existing model modules and preserve their browser and CommonJS exports so the app and Node tests can use the same code.

## Testing Guidelines

Add regression assertions beside related cases in `test.js` using `node:assert/strict`. Use fixed inputs for projection tests so results are reproducible. For service worker or asset changes, review the cache version and asset list in `dist/sw.js`, then verify offline reload after a successful online load. For storage changes, verify a saved plan reloads and that a JSON backup can be exported and imported.

## Commit & Pull Request Guidelines

Use a short, action-oriented commit subject. In a pull request, describe the behavior change, report the checks you ran, link any related issue, and include screenshots when the interface changes.
