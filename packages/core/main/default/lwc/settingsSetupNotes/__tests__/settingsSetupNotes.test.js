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

describe('c-settings-setup-notes', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows what, why and where for a section that needs Setup, without asking Apex', async () => {
    const element = await render('Duplicate Matching');

    const shown = note(element, 'duplicates');
    expect(shown).not.toBeNull();
    expect(shown.textContent).toContain('c.Core_SetupNote_Duplicates_What');
    expect(shown.textContent).toContain('c.Core_SetupNote_Duplicates_Why');
    expect(shown.textContent).toContain('c.Core_SetupNote_Duplicates_Where');
    expect(shown.querySelector('[data-id="status"]')).toBeNull();
    expect(shown.querySelector('lightning-icon').iconName).toBe('utility:info');
    expect(getSetupChecks).not.toHaveBeenCalled();
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
  });

  it('shows the notes a module page passes in, in place of any section', async () => {
    getSetupChecks.mockResolvedValue({ emailDeliverability: true });
    const element = createElement('c-settings-setup-notes', { is: SettingsSetupNotes });
    element.section = 'Households';
    element.notes = [
      { key: 'fromAddress', what: 'Add the address', why: 'Salesforce asks', where: 'Setup, X' },
      { key: 'pages', what: 'Assign the page', why: 'Only Setup', where: 'Setup, Y', met: false },
      {
        key: 'email',
        what: 'Send email',
        why: 'Digest',
        where: 'Setup, Z',
        check: 'emailDeliverability'
      }
    ];
    document.body.appendChild(element);
    await flushPromises();

    expect(note(element, 'duplicates')).toBeNull();
    const from = note(element, 'fromAddress');
    expect(from.textContent).toContain('Add the address');
    expect(from.textContent).toContain('Setup, X');
    expect(from.querySelector('[data-id="status"]')).toBeNull();
    expect(note(element, 'pages').querySelector('[data-id="status"]').textContent).toBe(
      'c.Core_SetupNote_NotDone'
    );
    expect(note(element, 'email').querySelector('[data-id="status"]').textContent).toBe(
      'c.Core_SetupNote_Done'
    );
    expect(getSetupChecks).toHaveBeenCalledTimes(1);
  });
});
