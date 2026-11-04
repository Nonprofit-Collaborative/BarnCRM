import { createElement } from 'lwc';
import ProgramsSettings from 'c/programsSettings';
import getSettings from '@salesforce/apex/ProgramsSettingsController.getSettings';
import savePrivacy from '@salesforce/apex/ProgramsSettingsController.savePrivacy';
import { format, picklistRows, privacyOptions, storedPrivacy } from '../settingsRows';

jest.mock(
  '@salesforce/apex/ProgramsSettingsController.getSettings',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ProgramsSettingsController.savePrivacy',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Programs_Settings_Default', () => ({ default: 'Default: {0}' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Programs_Settings_ChangeFor',
  () => ({ default: 'Change {0} in Setup' }),
  { virtual: true }
);

const SETTINGS = {
  canManage: true,
  intakePicklists: [
    {
      label: 'Referral Source',
      apiName: 'Referral_Source__c',
      values: ['Self', 'School'],
      defaultValue: null,
      setupUrl: '/lightning/setup/ObjectManager/Enrollment__c/FieldsAndRelationships/00N1/view'
    },
    {
      label: 'Eligibility Status',
      apiName: 'Eligibility_Status__c',
      values: ['Not Screened', 'Eligible'],
      defaultValue: 'Not Screened',
      setupUrl: '/x'
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  const element = createElement('c-programs-settings', { is: ProgramsSettings });
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('settingsRows (framework free)', () => {
  it('builds a row per picklist', () => {
    const rows = picklistRows(SETTINGS, { defaultValue: 'Default: {0}', changeFor: 'Change {0}' });
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      key: 'Referral_Source__c',
      choices: 'Self, School',
      defaultText: ''
    });
    expect(rows[1].defaultText).toBe('Default: Not Screened');
    expect(rows[1].linkLabel).toBe('Change Eligibility Status');
    expect(picklistRows(undefined, {})).toEqual([]);
    expect(format(undefined)).toBe('');
  });

  it('offers Shared first and reads the stored preset, Shared when unknown', () => {
    expect(privacyOptions({ shared: 'S', private: 'P' })).toEqual([
      { label: 'S', value: 'Shared' },
      { label: 'P', value: 'Private' }
    ]);
    expect(storedPrivacy({ participantPrivacy: 'Private' })).toBe('Private');
    expect(storedPrivacy({ participantPrivacy: 'Odd' })).toBe('Shared');
    expect(storedPrivacy(undefined)).toBe('Shared');
  });
});

describe('c-programs-settings', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the intake picklists with their Setup links', async () => {
    getSettings.mockResolvedValue(SETTINGS);
    const element = await render();
    expect(findAll(element, 'picklist')).toHaveLength(2);
    const link = findAll(element, 'setup-link')[0];
    expect(link.getAttribute('href')).toContain('FieldsAndRelationships/00N1/view');
    expect(link.getAttribute('aria-label')).toBe('Change Referral Source in Setup');
    expect(find(element, 'no-access')).toBeNull();
  });

  it('shows the stored preset and saves a new one', async () => {
    getSettings.mockResolvedValue({ ...SETTINGS, participantPrivacy: 'Shared' });
    savePrivacy.mockResolvedValue({ ...SETTINGS, participantPrivacy: 'Private' });
    const element = await render();
    const choice = find(element, 'privacy-choice');
    const bar = find(element, 'save-bar');
    expect(choice.value).toBe('Shared');
    expect(bar.dirtyCount).toBe(0);
    expect(find(element, 'privacy-default')).not.toBeNull();

    choice.dispatchEvent(new CustomEvent('change', { detail: { value: 'Private' } }));
    await flush();
    expect(bar.dirtyCount).toBe(1);

    bar.dispatchEvent(new CustomEvent('save'));
    await flush();
    expect(savePrivacy).toHaveBeenCalledWith({ privateParticipants: true });
    expect(find(element, 'saved').message).toBe('c.Programs_Settings_Saved');
    expect(bar.dirtyCount).toBe(0);
  });

  it('puts the stored preset back on Discard', async () => {
    getSettings.mockResolvedValue({ ...SETTINGS, participantPrivacy: 'Shared' });
    const element = await render();
    const choice = find(element, 'privacy-choice');
    choice.dispatchEvent(new CustomEvent('change', { detail: { value: 'Private' } }));
    await flush();
    find(element, 'save-bar').dispatchEvent(new CustomEvent('discard'));
    await flush();
    expect(choice.value).toBe('Shared');
    expect(find(element, 'save-bar').dirtyCount).toBe(0);
  });

  it('keeps the choice and says why when the save fails', async () => {
    getSettings.mockResolvedValue({ ...SETTINGS, participantPrivacy: 'Private' });
    savePrivacy.mockRejectedValue({});
    const element = await render();
    const choice = find(element, 'privacy-choice');
    choice.dispatchEvent(new CustomEvent('change', { detail: { value: 'Shared' } }));
    await flush();
    find(element, 'save-bar').dispatchEvent(new CustomEvent('save'));
    await flush();
    expect(savePrivacy).toHaveBeenCalledWith({ privateParticipants: false });
    expect(find(element, 'error').message).toContain('Programs_Fail_SettingsSave');
    expect(choice.value).toBe('Shared');
  });

  it('says so when the viewer cannot manage settings', async () => {
    getSettings.mockResolvedValue({ canManage: false, intakePicklists: [] });
    const element = await render();
    expect(find(element, 'no-access')).not.toBeNull();
    expect(find(element, 'picklists')).toBeNull();
  });

  it('shows a failure in its own words, or a general one', async () => {
    getSettings.mockRejectedValue({ body: { message: 'No.' } });
    const element = await render();
    expect(find(element, 'error').message).toBe('No.');

    getSettings.mockRejectedValue({});
    const second = await render();
    expect(second.shadowRoot.querySelector('[data-id="error"]').message).toContain(
      'Programs_Fail_SettingsLoad'
    );
  });
});
