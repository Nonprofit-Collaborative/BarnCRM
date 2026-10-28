import { createElement } from 'lwc';
import SettingsSetupNotes from 'c/settingsSetupNotes';
import getSetupChecks from '@salesforce/apex/SettingsController.getSetupChecks';

jest.mock('@salesforce/apex/SettingsController.getSetupChecks', () => ({ default: jest.fn() }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(section) {
  const element = createElement('c-settings-setup-notes', { is: SettingsSetupNotes });
  element.section = section;
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function note(element, key) {
  return element.shadowRoot.querySelector(`[data-key="${key}"]`);
}

function openLink(shown) {
  return shown.querySelector('[data-id="open-setup"]');
}

describe('c-settings-setup-notes', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows what, why and the steps for a section that needs Setup, without asking Apex', async () => {
    const element = await render('Duplicate Matching');

    const shown = note(element, 'duplicates');
    expect(shown).not.toBeNull();
    expect(shown.textContent).toContain('c.Core_SetupNote_Duplicates_What');
    expect(shown.textContent).toContain('c.Core_SetupNote_Duplicates_Why');
    expect(shown.querySelector('[data-id="steps"]').textContent).toContain(
      'c.Core_SetupNote_Duplicates_Steps'
    );
    expect(shown.querySelector('[data-id="status"]')).toBeNull();
    expect(shown.querySelector('[data-id="check-again"]')).toBeNull();
    expect(shown.querySelector('lightning-icon').iconName).toBe('utility:info');
    expect(getSetupChecks).not.toHaveBeenCalled();
  });

  it.each([
    ['General', 'metadata', '/lightning/setup/ApexSettings/home'],
    ['Duplicate Matching', 'duplicates', '/lightning/setup/DuplicateRules/home'],
    ['Rollups', 'rollupField', '/lightning/setup/ObjectManager/home'],
    ['Error Log', 'emailDeliverability', '/lightning/setup/OrgEmailSettings/home'],
    ['Access', 'users', '/lightning/setup/PermSets/home']
  ])('%s: Open in Setup opens %s at %s in a new tab', async (section, key, path) => {
    getSetupChecks.mockResolvedValue({});
    const link = openLink(note(await render(section), key));

    expect(link.getAttribute('href')).toBe(path);
    expect(link.getAttribute('target')).toBe('_blank');
    expect(link.getAttribute('rel')).toBe('noopener noreferrer');
    expect(link.textContent).toContain('c.Core_SetupNote_OpenInSetup');
    expect(link.textContent).toContain('c.Core_SetupNote_NewTab');
  });

  it('numbers each step a module passes, split on |, and shows no link for an unknown key', async () => {
    const element = createElement('c-settings-setup-notes', { is: SettingsSetupNotes });
    element.notes = [
      { key: 'a', what: 'W', why: 'Y', steps: 'Click Add.| Enter the address. |Click Save.|' },
      { key: 'b', what: 'W', why: 'Y', link: 'notAKey' }
    ];
    document.body.appendChild(element);
    await flushPromises();

    const steps = note(element, 'a').querySelectorAll('[data-id="steps"] li');
    expect(Array.from(steps).map((step) => step.textContent)).toEqual([
      'Click Add.',
      'Enter the address.',
      'Click Save.'
    ]);
    expect(openLink(note(element, 'a'))).toBeNull();
    expect(openLink(note(element, 'b'))).toBeNull();
    expect(note(element, 'b').querySelector('[data-id="steps"]')).toBeNull();
  });

  it('shows nothing for a section with no Setup step', async () => {
    const element = await render('Addresses');

    expect(element.shadowRoot.querySelectorAll('[data-key]')).toHaveLength(0);
  });

  it('no longer shows the duplicates note on Households, which moved to Duplicate Matching', async () => {
    const element = await render('Households');

    expect(note(element, 'duplicates')).toBeNull();
  });

  it('says Done when the check is met and Not done yet when it is not', async () => {
    getSetupChecks.mockResolvedValue({ emailDeliverability: true });
    const met = note(await render('Error Log'), 'emailDeliverability');
    expect(met.querySelector('[data-id="status"]').textContent).toBe('c.Core_SetupNote_Done');
    expect(met.querySelector('lightning-icon').iconName).toBe('utility:success');

    document.body.removeChild(document.body.firstChild);
    getSetupChecks.mockResolvedValue({ emailDeliverability: false });
    const errorLog = await render('Error Log');
    const email = note(errorLog, 'emailDeliverability');
    expect(email.querySelector('[data-id="status"]').textContent).toBe('c.Core_SetupNote_NotDone');
    expect(email.querySelector('lightning-icon').iconName).toBe('utility:warning');
  });

  it('Check Again reads the check again and shows the new answer', async () => {
    getSetupChecks.mockResolvedValue({ emailDeliverability: false });
    const element = await render('Error Log');
    const before = note(element, 'emailDeliverability');
    expect(before.querySelector('[data-id="status"]').textContent).toBe('c.Core_SetupNote_NotDone');

    getSetupChecks.mockResolvedValue({ emailDeliverability: true });
    before.querySelector('[data-id="check-again"]').click();
    await flushPromises();

    expect(getSetupChecks).toHaveBeenCalledTimes(2);
    const after = note(element, 'emailDeliverability');
    expect(after.querySelector('[data-id="status"]').textContent).toBe('c.Core_SetupNote_Done');
  });

  it('has no fiscal year note: the General page shows the Setup value as a row instead', async () => {
    const general = await render('General');

    expect(note(general, 'fiscalYear')).toBeNull();
    expect(note(general, 'metadata').querySelector('[data-id="status"]')).toBeNull();
    expect(getSetupChecks).not.toHaveBeenCalled();
  });

  it('asks Apex once however often the section changes', async () => {
    getSetupChecks.mockResolvedValue({ emailDeliverability: true });

    const element = await render('Error Log');
    element.section = 'Households';
    element.section = 'Error Log';
    await flushPromises();

    expect(getSetupChecks).toHaveBeenCalledTimes(1);
  });

  it('shows the instruction alone when the check cannot be read', async () => {
    getSetupChecks.mockRejectedValue(new Error('unavailable'));

    const element = await render('Error Log');

    const email = note(element, 'emailDeliverability');
    expect(email).not.toBeNull();
    expect(email.querySelector('[data-id="status"]')).toBeNull();
    expect(email.querySelector('lightning-icon').iconName).toBe('utility:info');
    expect(openLink(email)).not.toBeNull();
  });

  it('shows the notes a module page passes in, in place of any section', async () => {
    getSetupChecks.mockResolvedValue({ emailDeliverability: true });
    const element = createElement('c-settings-setup-notes', { is: SettingsSetupNotes });
    element.section = 'Households';
    element.notes = [
      {
        key: 'fromAddress',
        what: 'Add the address',
        why: 'Salesforce asks',
        steps: 'Click Add.',
        link: 'orgWideAddresses'
      },
      { key: 'pages', what: 'Assign the page', why: 'Only Setup', met: false },
      {
        key: 'email',
        what: 'Send email',
        why: 'Digest',
        link: 'deliverability',
        check: 'emailDeliverability'
      }
    ];
    document.body.appendChild(element);
    await flushPromises();

    expect(note(element, 'duplicates')).toBeNull();
    const from = note(element, 'fromAddress');
    expect(from.textContent).toContain('Add the address');
    expect(from.textContent).toContain('Click Add.');
    expect(openLink(from).getAttribute('href')).toBe('/lightning/setup/OrgWideEmailAddresses/home');
    expect(from.querySelector('[data-id="status"]')).toBeNull();
    expect(note(element, 'pages').querySelector('[data-id="status"]').textContent).toBe(
      'c.Core_SetupNote_NotDone'
    );
    const email = note(element, 'email');
    expect(email.querySelector('[data-id="status"]').textContent).toBe('c.Core_SetupNote_Done');
    expect(email.querySelector('[data-id="check-again"]')).not.toBeNull();
    expect(getSetupChecks).toHaveBeenCalledTimes(1);
  });
});
