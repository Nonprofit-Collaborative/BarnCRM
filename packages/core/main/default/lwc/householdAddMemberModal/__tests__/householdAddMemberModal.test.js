import { createElement } from 'lwc';
import HouseholdAddMemberModal from 'c/householdAddMemberModal';
import searchPeople from '@salesforce/apex/HouseholdOfPersonController.searchPeople';
import addExistingPerson from '@salesforce/apex/HouseholdOfPersonController.addExistingPerson';
import addNewPerson from '@salesforce/apex/HouseholdOfPersonController.addNewPerson';

jest.mock(
  '@salesforce/apex/HouseholdOfPersonController.searchPeople',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HouseholdOfPersonController.addExistingPerson',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HouseholdOfPersonController.addNewPerson',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const HOUSEHOLD_ID = '001000000000001AAA';
const MARIA = { id: '003000000000009AAA', name: 'Maria Garcia' };

function flush() {
  return Promise.resolve()
    .then(() => {})
    .then(() => {})
    .then(() => {});
}

/** The dialog as the panel opens it; closed records what it resolved with. */
function open(junctionMode) {
  const element = createElement('c-household-add-member-modal', { is: HouseholdAddMemberModal });
  Object.assign(element, { label: 'Add Member', householdId: HOUSEHOLD_ID, junctionMode });
  const closed = jest.fn();
  element.addEventListener('close', (event) => closed(event.detail));
  document.body.appendChild(element);
  return { element, closed, root: element.shadowRoot };
}

function type(root, selector, value) {
  const input = root.querySelector(selector);
  input.value = value;
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

async function search(root, term) {
  type(root, '.add-search-input', term);
  jest.runAllTimers();
  await flush();
}

describe('c-household-add-member-modal', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('holds the contact form with this household filled in, in the simple way', async () => {
    const { root, closed } = open(false);
    await flush();

    expect(root.querySelector('lightning-modal-header').label).toBe('Add Member');
    expect(root.querySelector('lightning-record-edit-form')).not.toBeNull();
    const fields = Array.from(root.querySelectorAll('lightning-input-field'));
    expect(fields.find((field) => field.fieldName === 'AccountId').value).toBe(HOUSEHOLD_ID);
    expect(root.querySelector('.add-search-input')).toBeNull();

    root.querySelector('lightning-record-edit-form').dispatchEvent(new CustomEvent('success'));
    expect(closed).toHaveBeenCalledWith(true);
  });

  it('offers a search and a new person form in the flexible way, and closes on Cancel', async () => {
    const { root, closed } = open(true);
    await flush();

    expect(root.querySelector('lightning-record-edit-form')).toBeNull();
    expect(root.querySelector('.add-search-input')).not.toBeNull();
    expect(root.querySelector('.add-new-last-name')).not.toBeNull();
    root.querySelector('.add-cancel-button').click();
    expect(closed).toHaveBeenCalledWith(false);
  });

  it('searches for an existing person and joins the one chosen', async () => {
    searchPeople.mockResolvedValue([MARIA]);
    const { root, closed } = open(true);
    await flush();
    await search(root, 'Maria');

    expect(searchPeople).toHaveBeenCalledWith({ searchTerm: 'Maria' });
    const result = root.querySelector('.add-existing-button');
    expect(result.label).toBe('Maria Garcia');
    expect(result.getAttribute('aria-label')).toBe('c.Core_HouseholdPanel_AddExistingResultFor');
    result.dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(addExistingPerson).toHaveBeenCalledWith({
      householdId: HOUSEHOLD_ID,
      personId: MARIA.id
    });
    expect(closed).toHaveBeenCalledWith(true);
  });

  it('ignores a slow search answer once the box was changed or cleared (UI-16)', async () => {
    let answerSlow;
    searchPeople.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          answerSlow = resolve;
        })
    );
    const { root } = open(true);
    await flush();
    await search(root, 'Maria');
    await search(root, '');
    answerSlow([MARIA]);
    await flush();

    expect(root.querySelector('.add-existing-button')).toBeNull();
  });

  it('says so in the dialog, which stays open, when adding an existing person is refused', async () => {
    searchPeople.mockResolvedValue([MARIA]);
    addExistingPerson.mockRejectedValue({ body: { message: 'That person could not be added.' } });
    const { root, closed } = open(true);
    await flush();
    await search(root, 'Maria');
    root.querySelector('.add-existing-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(root.querySelector('[role="alert"]').textContent).toContain(
      'That person could not be added.'
    );
    expect(closed).not.toHaveBeenCalled();
  });

  it('creates and joins a new person in the flexible way', async () => {
    const { root, closed } = open(true);
    await flush();
    type(root, '.add-new-salutation', 'Mr.');
    type(root, '.add-new-first-name', 'Wei');
    type(root, '.add-new-last-name', 'Lee');
    root.querySelector('.add-new-save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(addNewPerson).toHaveBeenCalledWith({
      householdId: HOUSEHOLD_ID,
      salutation: 'Mr.',
      firstName: 'Wei',
      lastName: 'Lee'
    });
    expect(closed).toHaveBeenCalledWith(true);
  });

  it('says so in plain words when adding a new person is refused', async () => {
    addNewPerson.mockRejectedValue({ body: { message: 'Enter at least a last name.' } });
    const { root, closed } = open(true);
    await flush();
    root.querySelector('.add-new-save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(root.querySelector('[role="alert"]').textContent).toContain(
      'Enter at least a last name.'
    );
    expect(closed).not.toHaveBeenCalled();
  });
});
