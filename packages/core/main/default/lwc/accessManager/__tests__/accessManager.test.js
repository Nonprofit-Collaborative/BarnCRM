import { createElement } from 'lwc';
import { createApexTestWireAdapter as mockCreateApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
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

const MARIA_ID = '005000000000001AAA';
const DAVID_ID = '005000000000002AAA';

const OVERVIEW = {
  success: true,
  canManage: true,
  currentUserId: MARIA_ID,
  errorCode: null,
  message: null,
  users: null,
  roles: [
    {
      developerName: 'Nonprofit_Admin_Group',
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
      roleDeveloperName: 'Nonprofit_Admin_Group',
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

    const confirmation = element.shadowRoot.querySelector('[data-id="confirmation"]');
    expect(confirmation).not.toBeNull();

    element.shadowRoot.querySelector('[data-id="confirm-button"]').click();
    await flush();

    expect(assignRole).toHaveBeenCalledWith({
      userId: DAVID_ID,
      roleDeveloperName: 'Fundraising_Staff'
    });
  });

  it('warns before someone removes their own BarnCRM Admin role', async () => {
    removeRole.mockResolvedValue({ success: true });
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    element.shadowRoot.querySelector('[data-id="remove-button"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="self-removal-warning"]')).not.toBeNull();

    element.shadowRoot.querySelector('[data-id="confirm-button"]').click();
    await flush();

    expect(removeRole).toHaveBeenCalledWith({
      userId: MARIA_ID,
      roleDeveloperName: 'Nonprofit_Admin_Group'
    });
  });

  it('closes the confirmation without changing anything when Cancel is used', async () => {
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    element.shadowRoot.querySelector('[data-id="remove-button"]').click();
    await flush();
    element.shadowRoot.querySelector('[data-id="cancel-button"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="confirmation"]')).toBeNull();
    expect(removeRole).not.toHaveBeenCalled();
  });

  it('offers the Setup link for creating a user', async () => {
    const element = createComponent();
    getAccessOverview.emit(OVERVIEW);
    await flush();

    const link = element.shadowRoot.querySelector('[data-id="setup-link"]');
    expect(link.href).toContain('/lightning/setup/ManageUsers/home');
  });
});
