/**
 * The accessibility assertion every component test makes (QA review Q5, D-200):
 *
 *   import { expectAccessible } from 'barn/a11y';
 *   ...
 *   await expectAccessible(element);
 *
 * It runs two layers. The first is BarnCRM's own checks below, which need no package: every
 * control has a name a screen reader can read (lightning-input, -combobox, -textarea and the
 * other form bases have a label; lightning-button has a label or title; lightning-button-icon
 * and lightning-button-menu have alternativeText or a label; a native button or link has text
 * or an aria-label), every img has alt, and nothing sets a positive tabindex. Lightning base
 * components are stubs under Jest, so these are checked on their public properties, which is
 * what axe cannot see. The second layer is @sa11y/jest (axe-core, Salesforce's ruleset) on the
 * rendered DOM, run whenever the package is installed (devDependency "@sa11y/jest"); until then
 * the first layer runs alone. scripts/ci/check-jest-a11y.py keeps the list of component tests
 * still without the assertion from growing.
 */

const NEEDS_LABEL = [
  'lightning-input',
  'lightning-combobox',
  'lightning-textarea',
  'lightning-dual-listbox',
  'lightning-radio-group',
  'lightning-checkbox-group',
  'lightning-slider',
  'lightning-input-rich-text',
  'lightning-record-picker'
];
const NEEDS_ALTERNATIVE_TEXT = ['lightning-button-icon', 'lightning-button-icon-stateful'];

function filled(value) {
  return value !== undefined && value !== null && String(value).trim() !== '';
}

/** Every element under `root`, through each component's shadow root. */
function allElements(root) {
  const found = [];
  const seen = new Set();
  const visit = (node) => {
    if (!node || seen.has(node)) {
      return;
    }
    seen.add(node);
    if (node.nodeType === 1) {
      found.push(node);
    }
    if (node.shadowRoot) {
      Array.from(node.shadowRoot.children).forEach(visit);
    }
    Array.from(node.children || []).forEach(visit);
  };
  visit(root);
  return found;
}

function describeElement(element) {
  const id = element.getAttribute('data-id') || element.getAttribute('name') || '';
  return id ? `${element.localName}[${id}]` : element.localName;
}

function hasNativeName(element) {
  return (
    filled(element.textContent) ||
    filled(element.getAttribute('aria-label')) ||
    filled(element.getAttribute('aria-labelledby')) ||
    filled(element.getAttribute('title'))
  );
}

/** What is wrong, one sentence per element; empty when nothing is. */
export function findA11yProblems(root) {
  const problems = [];
  for (const element of allElements(root)) {
    const name = element.localName;
    const where = describeElement(element);
    if (NEEDS_LABEL.includes(name) && !filled(element.label)) {
      problems.push(`${where} has no label (use variant="label-hidden" to hide it, not omit it)`);
    } else if (NEEDS_ALTERNATIVE_TEXT.includes(name) && !filled(element.alternativeText)) {
      problems.push(`${where} has no alternativeText`);
    } else if (
      name === 'lightning-button-menu' &&
      !filled(element.alternativeText) &&
      !filled(element.label)
    ) {
      problems.push(`${where} has neither a label nor alternativeText`);
    } else if (name === 'lightning-button' && !filled(element.label) && !filled(element.title)) {
      problems.push(`${where} has no label`);
    } else if (name === 'img' && !element.hasAttribute('alt')) {
      problems.push(`${where} has no alt (alt="" for a decorative image)`);
    } else if (
      (name === 'button' || (name === 'a' && element.hasAttribute('href'))) &&
      !hasNativeName(element)
    ) {
      problems.push(`${where} has no text or aria-label`);
    }
    const tabIndex = Number(element.getAttribute('tabindex'));
    if (tabIndex > 0) {
      problems.push(`${where} has tabindex ${tabIndex}; only 0 and -1 keep the reading order`);
    }
  }
  return problems;
}

let sa11y;
let sa11yLoaded = false;

function loadSa11y() {
  if (!sa11yLoaded) {
    sa11yLoaded = true;
    try {
      sa11y = require('@sa11y/jest');
      sa11y.registerSa11yMatcher();
    } catch {
      sa11y = undefined;
    }
  }
  return sa11y;
}

/** Fails the test with every accessibility problem found in the rendered component. */
export async function expectAccessible(element) {
  expect(findA11yProblems(element)).toEqual([]);
  if (loadSa11y()) {
    await expect(element).toBeAccessible();
  }
}
