// Jest stand-in for c/barnHelpText (jest.config.js moduleNameMapper). Help is always loaded, so
// components render at once, and a key reads as "c.<key>", the way sfdx-lwc-jest stubs a custom
// label, so tests written against the label stub keep their expectations. A test that needs
// real wording sets it with setHelpTextForTest({ key: 'text' }); clearHelpTextForTest() resets.
let overrides = {};

export function setHelpTextForTest(texts) {
  overrides = Object.assign({}, overrides, texts);
}

export function clearHelpTextForTest() {
  overrides = {};
}

export function loadHelp() {
  return Promise.resolve();
}

export function isHelpLoaded() {
  return true;
}

export function helpText(pkg, key, ...args) {
  const text = Object.prototype.hasOwnProperty.call(overrides, key) ? overrides[key] : 'c.' + key;
  return args.length
    ? text.replace(/\{(\d+)\}/g, (match, index) =>
        args[index] === undefined ? match : String(args[index])
      )
    : text;
}
