import { createElement } from 'lwc';
import OrganizationAddressSettings from 'c/organizationAddressSettings';
import getOrganizationAddress from '@salesforce/apex/SettingsController.getOrganizationAddress';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/SettingsController.getOrganizationAddress',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/SettingsController.saveSettings', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_OrganizationAddress_Save',
  () => ({ default: 'Save address' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_OrganizationAddress_Saved',
  () => ({ default: 'Address saved.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_OrganizationAddress_FillRequired',
  () => ({ default: 'Fill in the required parts.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_OrganizationAddress_LoadError',
  () => ({ default: 'Could not load.' }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/label/c.Core_Settings_SaveErrorMessage',
  () => ({ default: 'Could not save.' }),
  {
    virtual: true
  }
);

const EMPTY = {
  Organization_Street__c: '',
  Organization_Street_2__c: '',
  Organization_City__c: '',
  Organization_State__c: '',
  Organization_Postal_Code__c: '',
  Organization_Country__c: ''
};

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build(saved = EMPTY) {
  getOrganizationAddress.mockResolvedValue(saved);
  const element = createElement('c-organization-address-settings', {
    is: OrganizationAddressSettings
  });
  document.body.appendChild(element);
  await settle();
  return element;
}

function block(element) {
  return element.shadowRoot.querySelector('c-organization-address');
}

function type(element, key, value) {
  block(element).dispatchEvent(new CustomEvent('partchange', { detail: { key, value } }));
}

function saveButton(element) {
  return element.shadowRoot.querySelector('[data-id="save-address"]');
}

describe('c-organization-address-settings', () => {
  beforeEach(() => {
    saveSettings.mockReset();
    saveSettings.mockResolvedValue({});
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('opens on the address already saved', async () => {
    const element = await build({ ...EMPTY, Organization_City__c: 'Springfield' });

    expect(block(element).values.Organization_City__c).toBe('Springfield');
    expect(block(element).titled).toBeFalsy();
  });

  it('keeps Save disabled until something changes', async () => {
    const element = await build();
    expect(saveButton(element).disabled).toBe(true);

    type(element, 'Organization_Street__c', '14 Bridge Street');
    await settle();

    expect(saveButton(element).disabled).toBe(false);
  });

  it('saves every part through the settings console save, and says so', async () => {
    const element = await build();
    const saved = jest.fn();
    element.addEventListener('settingssaved', saved);
    type(element, 'Organization_Street__c', '14 Bridge Street');
    type(element, 'Organization_City__c', 'Springfield');
    type(element, 'Organization_State__c', 'IL');
    type(element, 'Organization_Postal_Code__c', '62701');
    await settle();

    saveButton(element).click();
    await settle();

    expect(saveSettings).toHaveBeenCalledWith({
      values: {
        ...EMPTY,
        Organization_Street__c: '14 Bridge Street',
        Organization_City__c: 'Springfield',
        Organization_State__c: 'IL',
        Organization_Postal_Code__c: '62701'
      }
    });
    expect(saved).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.textContent).toContain('Address saved.');
    expect(saveButton(element).disabled).toBe(true);
  });

  it('sends nothing while the block says a required part is blank', async () => {
    const element = await build();
    type(element, 'Organization_City__c', 'Springfield');
    await settle();
    jest.spyOn(block(element), 'reportValidity').mockReturnValue(false);

    saveButton(element).click();
    await settle();

    expect(saveSettings).not.toHaveBeenCalled();
    expect(element.shadowRoot.textContent).toContain('Fill in the required parts.');
  });

  it('shows the server message when the save is refused', async () => {
    const element = await build();
    saveSettings.mockRejectedValue({
      body: { message: 'The organization address is incomplete.' }
    });
    type(element, 'Organization_Street__c', '14 Bridge Street');
    await settle();

    saveButton(element).click();
    await settle();

    expect(element.shadowRoot.textContent).toContain('The organization address is incomplete.');
    expect(saveButton(element).disabled).toBe(false);
  });

  it('says so when the saved address cannot be loaded', async () => {
    getOrganizationAddress.mockRejectedValue(new Error('boom'));
    const element = createElement('c-organization-address-settings', {
      is: OrganizationAddressSettings
    });
    document.body.appendChild(element);
    await settle();

    expect(element.shadowRoot.textContent).toContain('Could not load.');
  });
});
