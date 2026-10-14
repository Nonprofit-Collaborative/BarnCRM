import { createElement } from 'lwc';
import { createApexTestWireAdapter as mockCreateApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import Toast from 'lightning/toast';
import BarnConfirmModal from 'c/barnConfirmModal';
import AccessManager from 'c/accessManager';
import getAccessOverview from '@salesforce/apex/AccessController.getAccessOverview';
import searchUsers from '@salesforce/apex/AccessController.searchUsers';
import assignAddOn from '@salesforce/apex/AccessController.assignAddOn';
import removeAddOn from '@salesforce/apex/AccessController.removeAddOn';

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/AccessController.getAccessOverview',
  () => ({ default: mockCreateApexTestWireAdapter(jest.fn()) }),
  { virtual: true }
);
jest.mock('@salesforce/apex/AccessController.searchUsers', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/AccessController.assignRole', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/AccessController.removeRole', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/AccessController.assignAddOn', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/AccessController.removeAddOn', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Access_RemovePerson', () => ({ default: 'Remove {0}' }), {
  virtual: true
});

const MARIA_ID = '005000000000001AAA';
const PRIYA_ID = '005000000000003AAA';
const WARNING = 'This permission lets the person remove data.';

const OVERVIEW = {
  success: true,
  canManage: true,
  canAssignAddOns: true,
  currentUserId: MARIA_ID,
  roles: [
    {
      developerName: 'BarnCRM_Admin_Group',
      label: 'BarnCRM Admin',
      description: 'For the person who configures the app.',
      isReady: true
    }
  ],
  assignments: [
    {
      roleDeveloperName: 'BarnCRM_Admin_Group',
      users: [{ userId: MARIA_ID, name: 'Maria Alvarez', email: 'maria@example.invalid' }]
    }
  ],
  addOns: [
    {
      developerName: 'BarnCRM_Find_And_Export',
      label: 'BarnCRM Find and Export',
      description: 'Build, run, save and\n export Find queries.',
      isDestructive: false,
      warning: null
    },
    {
      developerName: 'BarnCRM_Erase_People',
      label: 'BarnCRM Erase People',
      description: 'Erase a person on their request.',
      isDestructive: true,
      warning: WARNING
    }
  ],
  addOnAssignments: [
    { permissionSetName: 'BarnCRM_Find_And_Export', users: [] },
    {
      permissionSetName: 'BarnCRM_Erase_People',
      users: [{ userId: PRIYA_ID, name: 'Priya Nair', email: 'priya@example.invalid' }]
    }
  ]
};

function createComponent() {
  const element = createElement('c-access-manager', { is: AccessManager });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve();
}

async function choosePriya(element) {
  searchUsers.mockResolvedValue({
    success: true,
    users: [{ userId: PRIYA_ID, name: 'Priya Nair', email: 'priya@example.invalid' }]
  });
  const search = element.shadowRoot.querySelector('[data-id="user-search"]');
  search.value = 'Priya';
  search.dispatchEvent(new CustomEvent('change'));
  await flush();
  await flush();
  element.shadowRoot.querySelector('[data-id="user-option"]').click();
  await flush();
}

describe('c-access-manager extra permissions', () => {
  beforeEach(() => {
    BarnConfirmModal.open.mockResolvedValue(true);
    jest.spyOn(Toast, 'show');
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists each extra permission with what it grants, who has it, and a warning when it removes data', async () => {
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    const cards = element.shadowRoot.querySelectorAll('[data-id="add-on-card"]');
    expect(cards.length).toBe(2);
    const headings = element.shadowRoot.querySelectorAll('[data-id="add-on-heading"]');
    expect(headings[0].textContent).toBe('BarnCRM Find and Export (0)');
    expect(headings[1].textContent).toBe('BarnCRM Erase People (1)');
    const descriptions = element.shadowRoot.querySelectorAll('[data-id="add-on-card-description"]');
    expect(descriptions[0].textContent).toBe('Build, run, save and export Find queries.');
    const warnings = element.shadowRoot.querySelectorAll('[data-id="add-on-card-warning"]');
    expect(warnings.length).toBe(1);
    expect(warnings[0].textContent).toBe(WARNING);
    expect(element.shadowRoot.querySelector('[data-id="empty-add-on"]')).not.toBeNull();
    const remove = element.shadowRoot.querySelector('[data-id="add-on-remove-button"]');
    expect(remove.title).toBe('Remove Priya Nair');
  });

  it('shows the description and warning of the chosen permission, then gives it after a warned confirmation', async () => {
    assignAddOn.mockResolvedValue({ success: true });
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();
    await choosePriya(element);

    const button = element.shadowRoot.querySelector('[data-id="add-on-add-button"]');
    expect(button.disabled).toBe(true);

    const picker = element.shadowRoot.querySelector('[data-id="add-on-picker"]');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'BarnCRM_Erase_People' } }));
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="add-on-description"]').textContent).toBe(
      'Erase a person on their request.'
    );
    expect(element.shadowRoot.querySelector('[data-id="add-on-warning"]').textContent).toContain(
      WARNING
    );
    expect(button.disabled).toBe(false);

    button.click();
    await flush();
    await flush();

    const dialog = BarnConfirmModal.open.mock.calls[0][0];
    expect(dialog.confirmLabel).toBe('c.Core_Access_AddOnAddButton');
    expect(dialog.details).toEqual([WARNING]);
    expect(assignAddOn).toHaveBeenCalledWith({
      userId: PRIYA_ID,
      permissionSetName: 'BarnCRM_Erase_People'
    });
    await flush();
    expect(Toast.show).toHaveBeenCalledWith(
      expect.objectContaining({ variant: 'success' }),
      expect.anything()
    );
  });

  it('gives a permission that removes no data without a warning', async () => {
    assignAddOn.mockResolvedValue({ success: true });
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();
    await choosePriya(element);

    const picker = element.shadowRoot.querySelector('[data-id="add-on-picker"]');
    picker.dispatchEvent(
      new CustomEvent('change', { detail: { value: 'BarnCRM_Find_And_Export' } })
    );
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-on-warning"]')).toBeNull();

    element.shadowRoot.querySelector('[data-id="add-on-add-button"]').click();
    await flush();
    await flush();

    expect(BarnConfirmModal.open.mock.calls[0][0].details).toEqual([]);
  });

  it('shows the per person refusal from Salesforce as a sticky error', async () => {
    assignAddOn.mockResolvedValue({
      success: false,
      message: 'Priya Nair could not be given BarnCRM Erase People.'
    });
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();
    await choosePriya(element);
    element.shadowRoot
      .querySelector('[data-id="add-on-picker"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'BarnCRM_Erase_People' } }));
    await flush();

    element.shadowRoot.querySelector('[data-id="add-on-add-button"]').click();
    await flush();
    await flush();
    await flush();

    expect(Toast.show).toHaveBeenCalledWith(
      expect.objectContaining({
        message: 'Priya Nair could not be given BarnCRM Erase People.',
        variant: 'error',
        mode: 'sticky'
      }),
      expect.anything()
    );
  });

  it('removes a permission from a person, without the warning', async () => {
    removeAddOn.mockResolvedValue({ success: true });
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    element.shadowRoot.querySelector('[data-id="add-on-remove-button"]').click();
    await flush();
    await flush();

    const dialog = BarnConfirmModal.open.mock.calls[0][0];
    expect(dialog.confirmLabel).toBe('c.Core_Access_RemoveButton');
    expect(dialog.details).toEqual([]);
    expect(removeAddOn).toHaveBeenCalledWith({
      userId: PRIYA_ID,
      permissionSetName: 'BarnCRM_Erase_People'
    });
  });

  it('shows the cards with a notice and no buttons to a person who cannot assign permission sets', async () => {
    const element = createComponent();
    getAccessOverview.emit({ ...OVERVIEW, canAssignAddOns: false });
    await flush();

    expect(element.shadowRoot.querySelectorAll('[data-id="add-on-card"]').length).toBe(2);
    expect(element.shadowRoot.querySelector('[data-id="add-ons-read-only"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="add-on-picker"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="add-on-remove-button"]')).toBeNull();
    // Roles are unaffected: the person may still give a role.
    expect(element.shadowRoot.querySelector('[data-id="add-button"]')).not.toBeNull();
  });

  it('shows no extra permission controls in read-only mode and no section when the org has none', async () => {
    const element = createComponent();
    getAccessOverview.emit({ ...OVERVIEW, canManage: false, canAssignAddOns: false });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-on-picker"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="add-ons-read-only"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="add-on-remove-button"]')).toBeNull();

    getAccessOverview.emit({ ...OVERVIEW, addOns: [], addOnAssignments: [] });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-ons-section"]')).toBeNull();
  });
});
