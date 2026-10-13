import { createElement } from 'lwc';
import PersonErasure from 'c/personErasure';
import getPreview from '@salesforce/apex/PersonErasureController.preview';
import erasePerson from '@salesforce/apex/PersonErasureController.erase';

jest.mock('@salesforce/customPermission/Erase_People', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/apex/PersonErasureController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/PersonErasureController.erase', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_EraseAction_Confirm', () => ({ default: 'Type {0}' }), {
  virtual: true
});

const CHANGES = [
  { action: 'Cleared', objectLabel: 'Contact', count: 1, fields: ['Email', 'Phone'] },
  { action: 'Kept', objectLabel: 'Receipt', count: 2, fields: [], note: 'Tax records' }
];

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function build() {
  const element = createElement('c-person-erasure', { is: PersonErasure });
  element.recordId = '003000000000001AAA';
  document.body.appendChild(element);
  return element;
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function previewed(element) {
  getPreview.mockResolvedValue({ personName: 'Jordan Lee', changes: CHANGES, erased: false });
  byId(element, 'preview').click();
  await flush();
}

describe('c-person-erasure', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists what the preview would change, and keeps Erase off until the name is typed', async () => {
    const element = build();
    await previewed(element);

    const table = byId(element, 'changes');
    expect(getPreview).toHaveBeenCalledWith({ personId: '003000000000001AAA' });
    expect(table.data).toHaveLength(2);
    expect(table.data[0].fieldList).toBe('Email, Phone');
    expect(table.data[1].note).toBe('Tax records');
    expect(byId(element, 'confirm').label).toBe('Type Jordan Lee');
    expect(byId(element, 'erase').disabled).toBe(true);

    const confirm = byId(element, 'confirm');
    confirm.value = ' jordan   LEE ';
    confirm.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(byId(element, 'erase').disabled).toBe(false);
  });

  it('erases with the typed name and the request reference, then offers the audit record', async () => {
    const element = build();
    await previewed(element);
    erasePerson.mockResolvedValue({
      erased: true,
      erasureId: 'a0X000000000001AAA',
      changes: CHANGES
    });
    const reference = byId(element, 'reference');
    reference.value = 'PR-2041';
    reference.dispatchEvent(new CustomEvent('change'));
    const confirm = byId(element, 'confirm');
    confirm.value = 'Jordan Lee';
    confirm.dispatchEvent(new CustomEvent('change'));
    await flush();

    byId(element, 'erase').click();
    await flush();

    expect(erasePerson).toHaveBeenCalledWith({
      personId: '003000000000001AAA',
      typedName: 'Jordan Lee',
      requestReference: 'PR-2041'
    });
    expect(byId(element, 'done')).not.toBeNull();
    expect(byId(element, 'open-audit')).not.toBeNull();
    expect(byId(element, 'erase')).toBeNull();
  });

  it('shows a refusal in its own words', async () => {
    const element = build();
    getPreview.mockRejectedValue({ body: { message: 'You cannot change 3 Relationships' } });
    byId(element, 'preview').click();
    await flush();

    expect(byId(element, 'error').value).toBe('You cannot change 3 Relationships');
    expect(byId(element, 'changes')).toBeNull();
  });
});
