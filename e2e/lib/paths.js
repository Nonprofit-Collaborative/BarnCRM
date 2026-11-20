// Where a run keeps its output. Everything here is under e2e-results/, which git ignores.

const path = require('path');

const RESULTS = path.resolve(__dirname, '..', '..', 'e2e-results');

function orgAlias() {
  const alias = process.env.E2E_ORG;
  if (!alias) {
    throw new Error('Set E2E_ORG to an sf CLI org alias, or run scripts/org/run-e2e.sh <alias>.');
  }
  return alias;
}

const authDir = () => path.join(RESULTS, '.auth');
// Session cookies: never commit, share or attach this file.
const stateFile = () => path.join(authDir(), `${orgAlias()}.json`);
// The org's origin and its tabs and apps: no secrets.
const orgFile = () => path.join(authDir(), `${orgAlias()}.org.json`);

module.exports = { RESULTS, authDir, orgAlias, orgFile, stateFile };
