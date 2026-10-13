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
    const element = await render('Households');

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

  it('says Done when the check is met and Not done yet when it is not', async () => {
    getSetupChecks.mockResolvedValue({ fiscalYear: true, emailDeliverability: false });

    const general = await render('General');
    const fiscal = note(general, 'fiscalYear');
    expect(fiscal.querySelector('[data-id="status"]').textContent).toBe('c.Core_SetupNote_Done');
    expect(fiscal.querySelector('lightning-icon').iconName).toBe('utility:success');
    expect(note(general, 'metadata').querySelector('[data-id="status"]')).toBeNull();

    const errorLog = await render('Error Log');
    const email = note(errorLog, 'emailDeliverability');
    expect(email.querySelector('[data-id="status"]').textContent).toBe('c.Core_SetupNote_NotDone');
    expect(email.querySelector('lightning-icon').iconName).toBe('utility:warning');
  });

  it('asks Apex once however often the section changes', async () => {
    getSetupChecks.mockResolvedValue({ fiscalYear: true });

    const element = await render('General');
    element.section = 'Households';
    element.section = 'General';
    await flushPromises();

    expect(getSetupChecks).toHaveBeenCalledTimes(1);
  });

  it('shows the instruction alone when the check cannot be read', async () => {
    getSetupChecks.mockRejectedValue(new Error('unavailable'));

    const element = await render('General');

    const fiscal = note(element, 'fiscalYear');
    expect(fiscal).not.toBeNull();
    expect(fiscal.querySelector('[data-id="status"]')).toBeNull();
    expect(fiscal.querySelector('lightning-icon').iconName).toBe('utility:info');
  });
});
