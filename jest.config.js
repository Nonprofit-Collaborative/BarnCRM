const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
  ...jestConfig,
  roots: ['<rootDir>/packages'],
  moduleNameMapper: {
    // sfdx-lwc-jest ships no stub for lightning/actions, which a quick action screen uses to
    // close itself.
    '^lightning/actions$': '<rootDir>/packages/giving/test/jest-mocks/lightning/actions.js',
    // Nor for lightning/modal, the base of c/barnConfirmModal.
    '^lightning/modal$': '<rootDir>/packages/core/test/jest-mocks/lightning/modal.js',
    // One module id for lightning/toast, so a test's spy on Toast.show is the one the component
    // calls (the same per-directory caching problem as lightning/navigation below).
    '^lightning/toast$':
      '<rootDir>/node_modules/@salesforce/sfdx-lwc-jest/src/lightning-stubs/toast/toast.js',
    // Map to the sfdx-lwc-jest stub explicitly so every file resolves one module id. Through the
    // custom resolver alone, jest caches the id per importing directory without regard to virtual
    // mocks, so a test that mocks it (setupStepFields) lost to the unmocked stub whenever a test
    // rendering that component without the mock (setupAssistant) ran first in the same worker.
    '^lightning/navigation$':
      '<rootDir>/node_modules/@salesforce/sfdx-lwc-jest/src/lightning-stubs/navigation/navigation.js',
    // Same reason: c/workspaceTabs and the components that use it must share one stub, so a
    // test that emits a tab id or checks openSubtab sees the module the component imported.
    '^lightning/platformWorkspaceApi$':
      '<rootDir>/node_modules/@salesforce/sfdx-lwc-jest/src/lightning-stubs/platformWorkspaceApi/platformWorkspaceApi.js'
  },
  // No LWC components exist yet in any package; allow jest to pass cleanly until they do.
  passWithNoTests: true
};
