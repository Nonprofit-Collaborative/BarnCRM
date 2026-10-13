import { createElement } from 'lwc';
import HouseholdNamingSettings from 'c/householdNamingSettings';
import preview from '@salesforce/apex/HouseholdController.preview';
import getNamingSettings from '@salesforce/apex/HouseholdController.getNamingSettings';
import recomputeAll from '@salesforce/apex/HouseholdController.recomputeAll';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';

jest.mock(
  '@salesforce/apex/HouseholdController.preview',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdController.getNamingSettings',
  () => ({ default: jest.fn(() => Promise.resolve(null)) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdController.recomputeAll',
  () => ({ default: jest.fn(() => Promise.resolve('')) }),
  { virtual: true }
);

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/SettingsController.saveSettings',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const SAVED = {
  namePattern: '{LastName} Household',
  formalPattern: '{Salutation} {LastName}',
  informalPattern: '{FirstName}',
  includeDeceasedInName: false,
  canEdit: true
};

const SAMPLES = [
  {
    members: 'John Smith, Jane Smith',
    name: 'The Smith Family',
    formalGreeting: 'Mr. and Mrs. John Smith',
    informalGreeting: 'John and Jane'
  },
  {
    members: 'Maria Garcia',
    name: 'The Garcia Family',
    formalGreeting: 'Ms. Maria Garcia',
    informalGreeting: 'Maria'
  }
];

// Lets every promise the component started settle, including the settings load that the
// first preview waits for.
function flush() {
  return Promise.resolve()
    .then(() => {})
    .then(() => {})
    .then(() => {})
    .then(() => {})
    .then(() => {});
}

function build() {
  const element = createElement('c-household-naming-settings', { is: HouseholdNamingSettings });
  document.body.appendChild(element);
  return element;
}

describe('c-household-naming-settings', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    preview.mockResolvedValue(SAMPLES);
    getNamingSettings.mockResolvedValue(SAVED);
    recomputeAll.mockResolvedValue('707000000000000AAA');
    saveSettings.mockResolvedValue();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows a preview row for each sample household', async () => {
    const element = build();
    await flush();
    await flush();

    const rows = element.shadowRoot.querySelectorAll('.sample-row');
    expect(preview).toHaveBeenCalled();
    expect(rows.length).toBe(2);
    expect(rows[0].textContent).toContain('The Smith Family');
    expect(element.shadowRoot.querySelector('table').getAttribute('aria-label')).toBe(
      'c.Core_HouseholdNamingSettings_PreviewHeading'
    );
  });

  it('waits 300 milliseconds after typing before asking for a new preview', async () => {
    const element = build();
    await flush();
    preview.mockClear();

    const input = element.shadowRoot.querySelectorAll('lightning-input')[0];
    input.dispatchEvent(new CustomEvent('change', { detail: { value: '{LastName} Household' } }));

    jest.advanceTimersByTime(299);
    expect(preview).not.toHaveBeenCalled();

    jest.advanceTimersByTime(1);
    expect(preview).toHaveBeenCalledWith(
      expect.objectContaining({ namePattern: '{LastName} Household' })
    );
  });

  it('saves the three patterns together', async () => {
    const element = build();
    await flush();

    element.shadowRoot.querySelector('.save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(saveSettings).toHaveBeenCalledWith({
      settings: {
        Household_Name_Pattern__c: '{LastName} Household',
        Formal_Greeting_Pattern__c: '{Salutation} {LastName}',
        Informal_Greeting_Pattern__c: '{FirstName}'
      }
    });
  });

  it('disables Save while a save is in progress, so a double click cannot write twice', async () => {
    let resolveSave;
    saveSettings.mockReturnValue(
      new Promise((resolve) => {
        resolveSave = resolve;
      })
    );
    const element = build();
    await flush();

    const saveButton = element.shadowRoot.querySelector('.save-button');
    expect(saveButton.disabled).toBe(false);

    saveButton.dispatchEvent(new CustomEvent('click'));
    await flush();
    expect(saveButton.disabled).toBe(true);

    resolveSave();
    await flush();
    expect(saveButton.disabled).toBe(false);
  });

  it('dispatches a save event once the patterns are saved, so the Setup Assistant can tick its step', async () => {
    const element = build();
    await flush();

    const handler = jest.fn();
    element.addEventListener('save', handler);
    element.shadowRoot.querySelector('.save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail.values).toEqual({
      Household_Name_Pattern__c: '{LastName} Household',
      Formal_Greeting_Pattern__c: '{Salutation} {LastName}',
      Informal_Greeting_Pattern__c: '{FirstName}'
    });
  });

  it('asks for confirmation before recomputing every household', async () => {
    const element = build();
    await flush();

    element.shadowRoot.querySelector('.recompute-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    expect(recomputeAll).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('.confirm-box')).not.toBeNull();

    element.shadowRoot.querySelector('.confirm-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    expect(recomputeAll).toHaveBeenCalled();
  });

  it('leaves the fields editable for a user who may change settings', async () => {
    const element = build();
    await flush();

    const inputs = element.shadowRoot.querySelectorAll('lightning-input');
    expect(inputs.length).toBe(3);
    inputs.forEach((input) => expect(input.disabled).toBe(false));
  });

  it('opens on the patterns this org has saved, not on the shipped ones', async () => {
    const element = build();
    await flush();
    await flush();
    await flush();

    const inputs = element.shadowRoot.querySelectorAll('lightning-input');
    expect(getNamingSettings).toHaveBeenCalled();
    expect(inputs[0].value).toBe('{LastName} Household');
    expect(inputs[1].value).toBe('{Salutation} {LastName}');
    expect(inputs[2].value).toBe('{FirstName}');
    expect(preview).toHaveBeenCalledWith(
      expect.objectContaining({ namePattern: '{LastName} Household' })
    );
  });

  it('falls back to the shipped patterns where this org has saved none', async () => {
    getNamingSettings.mockResolvedValue({ namePattern: null, formalPattern: null });
    const element = build();
    await flush();
    await flush();
    await flush();

    const inputs = element.shadowRoot.querySelectorAll('lightning-input');
    expect(inputs[0].value).toBe('The {LastName} Family');
    expect(inputs[1].value).toBe('{Salutation} {FirstName} {LastName}');
  });

  it('shows what went wrong when the preview cannot be produced', async () => {
    preview.mockRejectedValue({ body: { message: 'Naming is not set up yet' } });
    const element = build();
    await flush();
    await flush();
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert).not.toBeNull();
    expect(alert.textContent).toContain('Naming is not set up yet');
  });
});
