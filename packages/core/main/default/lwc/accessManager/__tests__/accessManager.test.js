import { createElement } from 'lwc';
import { createApexTestWireAdapter as mockCreateApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import Toast from 'lightning/toast';
import BarnConfirmModal from 'c/barnConfirmModal';
import AccessManager from 'c/accessManager';
import getAccessOverview from '@salesforce/apex/AccessController.getAccessOverview';
import searchUsers from '@salesforce/apex/AccessController.searchUsers';
import assignRole from '@salesforce/apex/AccessController.assignRole';
import removeRole from '@salesforce/apex/AccessController.removeRole';

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
jest.mock('@salesforce/label/c.Core_Access_RemovePerson', () => ({ default: 'Remove {0}' }), {
  virtual: true
});

const MARIA_ID = '005000000000001AAA';
const DAVID_ID = '005000000000002AAA';

const OVERVIEW = {
  success: true,
  canManage: true,
  canChangeAccess: true,
  currentUserId: MARIA_ID,
  errorCode: null,
  message: null,
  users: null,
  roles: [
    {
      developerName: 'BarnCRM_Admin_Group',
      label: 'BarnCRM Admin',
      description: 'For the person who configures the app.',
      isReady: true
    },
    {
      developerName: 'Fundraising_Staff',
      label: 'Fundraising Staff',
      description: 'For development\n      and fundraising staff.',
      isReady: true
    }
  ],
  assignments: [
    {
      roleDeveloperName: 'BarnCRM_Admin_Group',
      users: [{ userId: MARIA_ID, name: 'Maria Alvarez', email: 'maria@example.invalid' }]
    },
    { roleDeveloperName: 'Fundraising_Staff', users: [] }
  ]
};

/**
 * Puts the component on the page.
 *
 * @returns {HTMLElement} the component
 */
function createComponent() {
  const element = createElement('c-access-manager', { is: AccessManager });
  document.body.appendChild(element);
  return element;
}

/**
 * Waits for the component to finish rendering.
 *
 * @returns {Promise} a promise that settles after the next render
 */
function flush() {
  return Promise.resolve();
}

describe('c-access-manager', () => {
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

  it('lists each role with the people who hold it', async () => {
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    const cards = element.shadowRoot.querySelectorAll('[data-id="role-card"]');
    expect(cards.length).toBe(2);
    const descriptions = element.shadowRoot.querySelectorAll('[data-id="role-description"]');
    expect(descriptions[1].textContent).toBe('For development and fundraising staff.');
    const headings = element.shadowRoot.querySelectorAll('[data-id="role-heading"]');
    expect(headings[0].textContent).toBe('BarnCRM Admin (1)');
    expect(headings[1].textContent).toBe('Fundraising Staff (0)');
    const members = element.shadowRoot.querySelectorAll('[data-id="role-member"]');
    expect(members.length).toBe(1);
    expect(members[0].textContent).toContain('Maria Alvarez');
    expect(element.shadowRoot.querySelector('[data-id="empty-role"]')).not.toBeNull();
  });

  it('shows a notice and no controls when the person may not change roles', async () => {
    const element = createComponent();
    getAccessOverview.emit({ ...OVERVIEW, canManage: false });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="read-only-notice"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="add-button"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="remove-button"]')).toBeNull();
  });

  it('shows an error when the page cannot be loaded', async () => {
    const element = createComponent();
    getAccessOverview.emit({
      ...OVERVIEW,
      success: false,
      message: 'Something went wrong.',
      roles: [],
      assignments: []
    });
    await flush();

    const error = element.shadowRoot.querySelector('[data-id="load-error"]');
    expect(error).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="role-card"]').length).toBe(0);
  });

  it('explains a blank page to a person who may not read the roles', async () => {
    const element = createComponent();
    getAccessOverview.emit({
      ...OVERVIEW,
      canManage: false,
      success: false,
      message: 'You can see this page but you cannot see who holds each role.',
      roles: [],
      assignments: []
    });
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="read-only-notice"]')).not.toBeNull();
    const error = element.shadowRoot.querySelector('[data-id="load-error"]');
    expect(error).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="role-card"]').length).toBe(0);
  });

  it('searches for a person after typing and gives them a role', async () => {
    searchUsers.mockResolvedValue({
      success: true,
      users: [{ userId: DAVID_ID, name: 'David Okafor', email: 'david@example.invalid' }]
    });
    assignRole.mockResolvedValue({ success: true });

    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    const search = element.shadowRoot.querySelector('[data-id="user-search"]');
    search.value = 'David';
    search.dispatchEvent(new CustomEvent('change', { target: { value: 'David' } }));
    await flush();
    await flush();

    const options = element.shadowRoot.querySelectorAll('[data-id="user-option"]');
    expect(searchUsers).toHaveBeenCalledWith({ term: 'David' });
    expect(options.length).toBe(1);

    options[0].click();
    await flush();

    const picker = element.shadowRoot.querySelector('[data-id="role-picker"]');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'Fundraising_Staff' } }));
    await flush();

    element.shadowRoot.querySelector('[data-id="add-button"]').click();
    await flush();
    await flush();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
    const dialog = BarnConfirmModal.open.mock.calls[0][0];
    expect(dialog.label).toBe('c.Core_Access_ConfirmAddTitle');
    expect(dialog.confirmLabel).toBe('c.Core_Access_AddButton');
    expect(dialog.details).toEqual([]);
    expect(assignRole).toHaveBeenCalledWith({
      userId: DAVID_ID,
      roleDeveloperName: 'Fundraising_Staff'
    });
    await flush();
    expect(Toast.show).toHaveBeenCalledWith(
      expect.objectContaining({ variant: 'success' }),
      expect.anything()
    );
  });

  it('names each Remove button for its person from one label', async () => {
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();
    const remove = element.shadowRoot.querySelector('[data-id="remove-button"]');
    expect(remove.title).toBe('Remove Maria Alvarez');
    expect(remove.getAttribute('aria-label')).toBe('Remove Maria Alvarez');
  });

  it('warns before someone removes their own BarnCRM Admin role', async () => {
    removeRole.mockResolvedValue({ success: true });
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    element.shadowRoot.querySelector('[data-id="remove-button"]').click();
    await flush();
    await flush();

    const dialog = BarnConfirmModal.open.mock.calls[0][0];
    expect(dialog.label).toBe('c.Core_Access_ConfirmRemoveTitle');
    expect(dialog.confirmLabel).toBe('c.Core_Access_RemoveButton');
    expect(dialog.details).toEqual(['c.Core_Access_SelfRemovalWarning']);
    expect(removeRole).toHaveBeenCalledWith({
      userId: MARIA_ID,
      roleDeveloperName: 'BarnCRM_Admin_Group'
    });
  });

  it('shows a sticky error toast when a change is refused', async () => {
    removeRole.mockResolvedValue({ success: false, message: 'Not allowed.' });
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    element.shadowRoot.querySelector('[data-id="remove-button"]').click();
    await flush();
    await flush();
    await flush();

    expect(Toast.show).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Not allowed.', variant: 'error', mode: 'sticky' }),
      expect.anything()
    );
  });

  it('changes nothing when the confirmation is cancelled', async () => {
    BarnConfirmModal.open.mockResolvedValue(false);
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    element.shadowRoot.querySelector('[data-id="remove-button"]').click();
    await flush();
    await flush();

    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
    expect(removeRole).not.toHaveBeenCalled();
  });

  it('offers the Setup link for creating a user', async () => {
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    const link = element.shadowRoot.querySelector('[data-id="setup-link"]');
    expect(link.href).toContain('/lightning/setup/ManageUsers/home');
  });

  it('links to the automatic access guide, in a new tab, even in read-only mode', async () => {
    const element = createComponent();
    getAccessOverview.emit({ ...OVERVIEW, canManage: false });
    await flush();

    const link = element.shadowRoot.querySelector('[data-id="automatic-access-link"]');
    expect(link.href).toContain('docs/admin-guide/automatic-access.md');
    expect(link.target).toBe('_blank');
    expect(link.textContent).toContain('c.Core_Access_AutomaticAccessLink');
    expect(link.textContent).toContain('c.Core_Kit_NewTab');
  });
});
