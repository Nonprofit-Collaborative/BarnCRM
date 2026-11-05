import { createElement } from 'lwc';
import HouseholdAddMemberModal from 'c/householdAddMemberModal';
import searchPeople from '@salesforce/apex/HouseholdOfPersonController.searchPeople';
import addExistingPerson from '@salesforce/apex/HouseholdOfPersonController.addExistingPerson';
import addNewPerson from '@salesforce/apex/HouseholdOfPersonController.addNewPerson';
import findSameName from '@salesforce/apex/PersonSameNameController.findSameName';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';
import { describeSameNamePerson, joinName } from '../sameNameHint';

jest.mock(
  '@salesforce/apex/PersonSameNameController.findSameName',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);
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

    expect(root.querySelector('c-barn-notice.add-error').message).toBe(
      'That person could not be added.'
    );
    expect(root.querySelector('c-barn-notice.add-error').variant).toBe('error');
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

    expect(root.querySelector('c-barn-notice.add-error').message).toBe(
      'Enter at least a last name.'
    );
    expect(closed).not.toHaveBeenCalled();
  });

  describe('same-name hint (people-giving-24)', () => {
    const ANA = {
      id: '003000000000010AAA',
      name: 'Ana Garcia',
      city: 'Tampa',
      householdName: 'Garcia Household'
    };

    beforeEach(() => {
      setHelpTextForTest({
        Core_PersonSameName_Hint: 'Already in BarnCRM: {0}.',
        Core_PersonSameName_Use: 'Use this person instead?'
      });
    });

    afterEach(() => {
      clearHelpTextForTest();
    });

    it('names the existing person with city and household, and switches to them', async () => {
      findSameName.mockResolvedValue([ANA]);
      addExistingPerson.mockResolvedValue();
      const { root, closed } = open(true);
      await flush();
      type(root, '.add-new-first-name', 'Ana');
      type(root, '.add-new-last-name', 'Garcia');
      jest.runAllTimers();
      await flush();

      expect(findSameName).toHaveBeenLastCalledWith({
        firstName: 'Ana',
        lastName: 'Garcia',
        excludeHouseholdId: HOUSEHOLD_ID
      });
      const hint = root.querySelector('c-barn-notice.same-name-hint');
      expect(hint.message).toBe('Already in BarnCRM: Ana Garcia, Tampa (Garcia Household).');
      expect(hint.actionLabel).toBe('Use this person instead?');
      hint.dispatchEvent(new CustomEvent('action'));
      await flush();

      expect(addExistingPerson).toHaveBeenCalledWith({
        householdId: HOUSEHOLD_ID,
        personId: ANA.id
      });
      expect(closed).toHaveBeenCalledWith(true);
    });

    it('asks nothing until the last name has two letters', async () => {
      const { root } = open(true);
      await flush();
      type(root, '.add-new-last-name', 'G');
      jest.runAllTimers();
      await flush();

      expect(findSameName).not.toHaveBeenCalled();
      expect(root.querySelector('c-barn-notice.same-name-hint')).toBeNull();
    });

    it('shows the hint in the simple way too, from the contact form fields', async () => {
      findSameName.mockResolvedValue([ANA]);
      const { root } = open(false);
      await flush();
      const last = root.querySelector('.form-last-name');
      last.dispatchEvent(new CustomEvent('change', { detail: { value: 'Garcia' } }));
      jest.runAllTimers();
      await flush();

      expect(root.querySelector('c-barn-notice.same-name-hint')).not.toBeNull();
    });
  });

  describe('person mode (inline new person)', () => {
    function openPerson() {
      const element = createElement('c-household-add-member-modal', {
        is: HouseholdAddMemberModal
      });
      Object.assign(element, { label: 'New Person', mode: 'person' });
      const closed = jest.fn();
      element.addEventListener('close', (event) => closed(event.detail));
      document.body.appendChild(element);
      return { closed, root: element.shadowRoot };
    }

    it('shows the contact form with email and address and no household field', async () => {
      const { root } = openPerson();
      await flush();

      const names = Array.from(root.querySelectorAll('lightning-input-field')).map(
        (field) => field.fieldName
      );
      expect(names).toEqual(
        expect.arrayContaining([
          'FirstName',
          'LastName',
          'Email',
          'MailingStreet',
          'MailingCity',
          'MailingPostalCode'
        ])
      );
      expect(names).not.toContain('AccountId');
      expect(root.querySelector('.add-search-input')).toBeNull();
    });

    it('resolves the new person as { id, name } once the platform saved them', async () => {
      const { root, closed } = openPerson();
      await flush();
      root
        .querySelector('.form-first-name')
        .dispatchEvent(new CustomEvent('change', { detail: { value: 'Wei' } }));
      root
        .querySelector('.form-last-name')
        .dispatchEvent(new CustomEvent('change', { detail: { value: 'Lee' } }));
      root
        .querySelector('lightning-record-edit-form')
        .dispatchEvent(new CustomEvent('success', { detail: { id: '003000000000011AAA' } }));

      expect(closed).toHaveBeenCalledWith({ id: '003000000000011AAA', name: 'Wei Lee' });
    });

    it('resolves the existing person when the same-name hint is used, without asking Apex to join', async () => {
      findSameName.mockResolvedValue([{ id: '003000000000010AAA', name: 'Ana Garcia' }]);
      const { root, closed } = openPerson();
      await flush();
      root
        .querySelector('.form-last-name')
        .dispatchEvent(new CustomEvent('change', { detail: { value: 'Garcia' } }));
      jest.runAllTimers();
      await flush();

      expect(findSameName).toHaveBeenLastCalledWith({
        firstName: '',
        lastName: 'Garcia',
        excludeHouseholdId: null
      });
      root.querySelector('c-barn-notice.same-name-hint').dispatchEvent(new CustomEvent('action'));

      expect(closed).toHaveBeenCalledWith({ id: '003000000000010AAA', name: 'Ana Garcia' });
      expect(addExistingPerson).not.toHaveBeenCalled();
    });

    it('resolves nothing on Cancel', async () => {
      const { root, closed } = openPerson();
      await flush();
      root.querySelector('.add-cancel-button').click();

      expect(closed).toHaveBeenCalledTimes(1);
      expect(closed.mock.calls[0][0]).toBeFalsy();
    });
  });

  describe('sameNameHint module', () => {
    it('leaves out an unknown city or household', () => {
      expect(describeSameNamePerson({ name: 'Ana Garcia' })).toBe('Ana Garcia');
      expect(
        describeSameNamePerson({ name: 'Ana Garcia', householdName: 'Garcia Household' })
      ).toBe('Ana Garcia (Garcia Household)');
      expect(describeSameNamePerson(null)).toBe('');
      expect(joinName(' Wei ', undefined)).toBe('Wei');
    });
  });
});
