const fs = require('fs');
const path = require('path');
const lwcConfig = require('@salesforce/eslint-config-lwc/recommended');

// Pure modules: plain JavaScript with no Salesforce runtime in it, so the logic can be reused
// outside Salesforce and tested without stubs (portability, plan Section 4.4). A file belongs
// here when it is a helper inside a component bundle (its name differs from the bundle's) and
// works on plain values only. Add every new such module to this list; the rule below then
// keeps it from importing the platform. See docs/contributor-guide/ci.md, static step 3.
const PURE_MODULES = [
  'packages/core/main/default/lwc/importWizard/csv.js',
  'packages/core/main/default/lwc/importWizard/xlsx.js'
];

// A renamed or moved module would silently drop out of the rule, so a stale entry fails lint.
for (const file of PURE_MODULES) {
  if (!fs.existsSync(path.join(__dirname, file))) {
    throw new Error(`eslint.config.js PURE_MODULES lists ${file}, which does not exist.`);
  }
}

const PLATFORM_IMPORT_MESSAGE =
  'A pure module (eslint.config.js PURE_MODULES) may not import the Salesforce platform. ' +
  'Keep the platform call in the component and pass plain values in.';

module.exports = [
  {
    ignores: [
      'node_modules/**',
      '**/main/default/staticresources/**',
      '**/__tests__/**/*.snap',
      'coverage/**'
    ]
  },
  ...lwcConfig,
  {
    files: ['packages/**/lwc/**/*.js'],
    rules: {}
  },
  {
    files: PURE_MODULES,
    rules: {
      'no-restricted-imports': [
        'error',
        {
          paths: [{ name: 'lwc', message: PLATFORM_IMPORT_MESSAGE }],
          patterns: [{ group: ['lightning/*', '@salesforce/*'], message: PLATFORM_IMPORT_MESSAGE }]
        }
      ]
    }
  },
  {
    // Jest test files load the wire adapter factories with require() inside jest.mock, which is
    // hoisted above the imports, so require is available to them and to nothing else.
    files: ['packages/**/lwc/**/__tests__/**/*.js'],
    languageOptions: {
      globals: {
        require: 'readonly'
      }
    }
  },
  {
    // sampleDataManager (C-10) polls SampleDataController.getStatus while a load runs;
    // setInterval/clearInterval is the standard, supported way to do that in an LWC.
    files: ['packages/core/main/default/lwc/sampleDataManager/sampleDataManager.js'],
    rules: {
      '@lwc/lwc/no-async-operation': 'off'
    }
  },
  {
    // importWizard (C-14) polls ImportController.getBatch while a dry run or a commit runs,
    // for the same reason and by the same supported mechanism as sampleDataManager.
    files: ['packages/core/main/default/lwc/importWizard/importWizard.js'],
    rules: {
      '@lwc/lwc/no-async-operation': 'off'
    }
  },
  {
    // Test-only timer helpers: a real setTimeout to flush promises, and a microtask
    // drain loop used under jest.useFakeTimers().
    files: [
      'packages/core/main/default/lwc/sampleDataManager/__tests__/*.js',
      'packages/core/main/default/lwc/importWizard/__tests__/*.js'
    ],
    rules: {
      '@lwc/lwc/no-async-operation': 'off',
      'no-await-in-loop': 'off'
    }
  }
];
