'use strict';

const TrajectoryStorage = (() => {
  const legacyKey = 'trajectory-v1';
  const snapshotKey = 'plans.sqlite3';
  const { defaults, previousRules, startingAllocation } = Trajectory;

  function normalize(value) {
    if (!value || typeof value.active !== 'string' || !value.plans ||
        typeof value.plans !== 'object' || Array.isArray(value.plans) ||
        !Object.hasOwn(value.plans, value.active)) {
      throw new Error('This backup has no active plan.');
    }

    const plans = Object.create(null);
    for (const [name, plan] of Object.entries(value.plans)) {
      if (!name.trim() || !plan || typeof plan !== 'object' || Array.isArray(plan)) {
        throw new Error('This backup contains an invalid plan.');
      }
      const settings = { ...defaults, ...previousRules };
      for (const key of Object.keys(settings)) {
        const value = plan[key];
        if (typeof value === typeof settings[key] &&
            (typeof value !== 'number' || Number.isFinite(value))) {
          settings[key] = value;
        }
      }
      settings.startAge = Math.max(18, Math.min(100, Math.round(settings.startAge)));
      settings.startYear = Math.max(1900, Math.min(2200, Math.round(settings.startYear)));
      const allocation = startingAllocation(settings);
      settings.cashShare = allocation.cash;
      settings.rothShare = allocation.roth;
      settings.workplaceShare = allocation.workplace;
      const retirement = TrajectoryRetirement.normalize(plan.retirement);
      if (retirement) settings.retirement = retirement;
      plans[name] = settings;
    }
    return { active: value.active, plans };
  }

  function initialState() {
    try {
      const saved = localStorage.getItem(legacyKey);
      if (saved) return normalize(JSON.parse(saved));
    } catch {
      // A backup can still be imported if legacy browser storage is unavailable.
    }
    return null;
  }

  function openDisk() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open('trajectory-sqlite', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('database');
      request.onsuccess = () => {
        const disk = request.result;
        disk.onversionchange = () => disk.close();
        resolve(disk);
      };
      request.onerror = () => reject(request.error);
    });
  }

  function readPlans(db) {
    const plans = Object.create(null);
    db.each('SELECT name, assumptions FROM plans ORDER BY rowid', row => {
      plans[row.name] = JSON.parse(row.assumptions);
    });
    const [[active]] = db.exec('SELECT active_plan FROM preferences WHERE id = 1')[0].values;
    return normalize({ active, plans });
  }

  function writePlans(db, state) {
    db.run(`
      CREATE TABLE IF NOT EXISTS plans (
        name TEXT PRIMARY KEY,
        assumptions TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS preferences (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        active_plan TEXT NOT NULL REFERENCES plans (name)
      );
      PRAGMA user_version = 1;
      BEGIN;
      DELETE FROM preferences;
      DELETE FROM plans;
    `);
    for (const [name, plan] of Object.entries(state.plans)) {
      db.run('INSERT INTO plans (name, assumptions) VALUES (?, ?)', [name, JSON.stringify(plan)]);
    }
    db.run('INSERT INTO preferences (id, active_plan) VALUES (1, ?)', [state.active]);
    db.run('COMMIT');
  }

  async function open() {
    const SQL = await initSqlJs({ locateFile: file => './vendor/' + file });
    const disk = await openDisk();

    function access({ initialize = false, update, exportFile = false } = {}) {
      return new Promise((resolve, reject) => {
        // Keep each read and write in a single transaction, including across tabs.
        const transaction = disk.transaction('database', initialize || update ? 'readwrite' : 'readonly');
        const store = transaction.objectStore('database');
        const request = store.get(snapshotKey);
        let result, failure;

        request.onsuccess = () => {
          let db;
          try {
            const bytes = request.result;
            if (!bytes && exportFile) throw new Error('The saved database is missing.');
            if (exportFile) {
              result = bytes;
              return;
            }
            db = new SQL.Database(bytes);
            const current = bytes ? readPlans(db) : initialState();
            result = update ? normalize(update(current)) : current;
            if (result && (!bytes || update)) {
              writePlans(db, result);
              store.put(db.export(), snapshotKey);
            }
          } catch (error) {
            failure = error;
            transaction.abort();
          } finally {
            db?.close();
          }
        };
        transaction.oncomplete = () => resolve(result);
        transaction.onabort = () => reject(failure || transaction.error || new Error('The database transaction failed.'));
      });
    }

    try {
      const state = await access({ initialize: true });
      return {
        state,
        update: update => access({ update }),
        exportFile: () => access({ exportFile: true })
      };
    } catch (error) {
      disk.close();
      throw error;
    }
  }

  return { normalize, open };
})();
