import { createElement } from 'lwc';
import SetupStepSuite from 'c/setupStepSuite';

const DOCS = 'https://example.invalid/giving/README.md';
const INSTALLER = '/packaging/installPackage.apexp?p0=04t000000000001AAA';

function build(suite, canEdit = true) {
  const element = createElement('c-setup-step-suite', { is: SetupStepSuite });
  element.canEdit = canEdit;
  element.suite = suite;
  document.body.appendChild(element);
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-setup-step-suite', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('offers both editions and preselects the recommendation', () => {
    const element = build({
      currentSuite: null,
      recommendedSuite: 'Impact',
      giving: { present: true, docsUrl: DOCS }
    });

    const choice = find(element, 'suite-choice');
    expect(choice.options.map((option) => option.value)).toEqual(['Community', 'Impact']);
    expect(choice.value).toBe('Impact');
  });

  it('leaves a fresh org to choose for itself', () => {
    const element = build({ currentSuite: null, recommendedSuite: null, giving: {} });

    expect(find(element, 'suite-choice').value).toBeFalsy();
    expect(find(element, 'giving-needed')).toBeNull();
  });

  it('sends the chosen edition when Maria confirms', () => {
    const element = build({ currentSuite: null, recommendedSuite: null, giving: {} });
    const handler = jest.fn();
    element.addEventListener('confirm', handler);

    const choice = find(element, 'suite-choice');
    choice.dispatchEvent(new CustomEvent('change', { detail: { value: 'Community' } }));
    find(element, 'confirm').click();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({ suite: 'Community' });
  });

  it('links to the Giving installer in a new tab when the Nonprofit Edition needs it', () => {
    const element = build({
      currentSuite: 'Impact',
      giving: { present: false, docsUrl: DOCS, installUrl: INSTALLER }
    });

    expect(find(element, 'giving-needed').textContent).toContain('Core_SuiteChoice_GivingNeeded');
    const link = find(element, 'install-link');
    expect(link.getAttribute('href')).toBe(INSTALLER);
    expect(link.target).toBe('_blank');
    expect(find(element, 'no-install-link')).toBeNull();
  });

  it('says so when no Giving version is published, and links its description', () => {
    const element = build({
      currentSuite: 'Impact',
      giving: { present: false, docsUrl: DOCS, installUrl: null }
    });

    expect(find(element, 'install-link')).toBeNull();
    expect(find(element, 'no-install-link')).not.toBeNull();
    expect(find(element, 'docs-link').getAttribute('href')).toBe(DOCS);
  });

  it('asks the page to check again after an install', () => {
    const element = build({ currentSuite: 'Impact', giving: { present: false, docsUrl: DOCS } });
    const handler = jest.fn();
    element.addEventListener('checkagain', handler);

    find(element, 'check-again').click();

    expect(handler).toHaveBeenCalledTimes(1);
  });

  it('says Giving is installed and offers nothing to install', () => {
    const element = build({ currentSuite: 'Impact', giving: { present: true, docsUrl: DOCS } });

    expect(find(element, 'giving-installed')).not.toBeNull();
    expect(find(element, 'install-link')).toBeNull();
    expect(find(element, 'check-again')).toBeNull();
  });

  it('shows nothing about Giving with the Standard Edition saved', () => {
    const element = build({ currentSuite: 'Community', giving: { present: false } });

    expect(find(element, 'giving-needed')).toBeNull();
    expect(find(element, 'giving-installed')).toBeNull();
  });

  it('lets David read the choice without saving it', () => {
    const element = build({ currentSuite: null, recommendedSuite: 'Impact', giving: {} }, false);

    expect(find(element, 'suite-choice').disabled).toBe(true);
    expect(find(element, 'confirm')).toBeNull();
  });

  it('shows a saved edition read-only and no longer offers the choice', () => {
    const element = build({ currentSuite: 'Community', giving: {} });

    expect(find(element, 'suite-choice')).toBeNull();
    expect(find(element, 'confirm')).toBeNull();
    expect(find(element, 'suite-saved').textContent).toContain('Core_SuiteChoice_StandardName');
    const help = find(element, 'change-help');
    expect(help.getAttribute('href')).toContain('docs/admin-guide/editions.md');
    expect(help.target).toBe('_blank');
  });

  it('names the Nonprofit Edition when it is saved', () => {
    const element = build({ currentSuite: 'Impact', giving: { present: true, docsUrl: DOCS } });

    expect(find(element, 'suite-saved').textContent).toContain('Core_SuiteChoice_NonprofitName');
    expect(find(element, 'suite-choice')).toBeNull();
  });
});
