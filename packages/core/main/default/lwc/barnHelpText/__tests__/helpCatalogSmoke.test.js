// Smoke test: three pages' help loads from the real packaged catalogs through the real store,
// and every key those pages read comes back as text (ADR-0164 help-text-json).
import { createHelpStore } from 'c/barnHelpCatalog';

const fs = require('fs');

const PAGES = [
  'packages/core/main/default/lwc/orgOptimizer/orgOptimizer.js',
  'packages/core/main/default/lwc/importWizard/importWizard.js',
  'packages/rollups/main/default/lwc/rollupWizard/rollupWizard.js'
];
const FOLDERS = { Core: 'core', Rollups: 'rollups' };

function catalogFile(name) {
  const pkg = name.replace('BarnHelp_', '');
  const path = `packages/${FOLDERS[pkg]}/main/default/staticresources/${name}.json`;
  return fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, 'utf8')) : null;
}

describe('help catalogs (smoke)', () => {
  it.each(PAGES)('%s reads every help key it names', async (page) => {
    const source = fs.readFileSync(page, 'utf8');
    const calls = [...source.matchAll(/helpText\('(\w+)', '(\w+)'/g)].map((m) => [m[1], m[2]]);
    expect(calls.length).toBeGreaterThan(0);

    const fetchJson = jest.fn((url) => Promise.resolve(catalogFile(url)));
    const store = createHelpStore(fetchJson, (name) => name);
    await store.load([...new Set(calls.map(([pkg]) => pkg))], 'en-US');

    calls.forEach(([pkg, key]) => {
      expect(`${key}: ${store.text(pkg, key).length > 0}`).toBe(`${key}: true`);
    });
  });
});
