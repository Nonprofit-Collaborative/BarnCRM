import { createElement } from 'lwc';
import FindRadiusPanel from 'c/findRadiusPanel';
import listRadiusFields from '@salesforce/apex/FindController.listRadiusFields';
import resolveRadiusCenter from '@salesforce/apex/FindController.resolveRadiusCenter';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';

jest.mock('@salesforce/apex/FindController.listRadiusFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.resolveRadiusCenter', () => ({ default: jest.fn() }), {
  virtual: true
});

const FIELDS = [
  { label: 'Mailing Address', value: 'MailingAddress' },
  { label: 'Other Address', value: 'OtherAddress' }
];

// A macrotask, because the panel awaits Apex before it renders its choices.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount() {
  const element = createElement('c-find-radius-panel', { is: FindRadiusPanel });
  element.objectApiName = 'Contact';
  document.body.appendChild(element);
  await flush();
  return element;
}

function query(element, dataId) {
  return element.shadowRoot.querySelector(`[data-id="${dataId}"]`);
}

function change(target, value) {
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-find-radius-panel', () => {
  beforeEach(() => {
    listRadiusFields.mockResolvedValue(FIELDS);
    setHelpTextForTest({ Core_Find_RadiusCenterSet: 'Measuring from {0}.' });
  });

  afterEach(() => {
    clearHelpTextForTest();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('reports a radius only once a place is looked up, and the query waits until then', async () => {
    resolveRadiusCenter.mockResolvedValue({
      latitude: 42.3126,
      longitude: -71.0553,
      label: 'Postal code 02134'
    });
    const changed = jest.fn();
    const element = await mount();
    element.addEventListener('change', changed);

    query(element, 'add').click();
    await flush();
    expect(changed.mock.calls.pop()[0].detail).toEqual({ radius: undefined, valid: false });
    expect(query(element, 'needs-place')).not.toBeNull();

    change(query(element, 'place'), '02134');
    query(element, 'use').click();
    await flush();

    expect(resolveRadiusCenter).toHaveBeenCalledWith({ text: '02134' });
    expect(changed.mock.calls.pop()[0].detail).toEqual({
      radius: { field: 'MailingAddress', miles: 25, latitude: 42.3126, longitude: -71.0553 },
      valid: true
    });
    expect(query(element, 'center').textContent).toContain('Postal code 02134');

    change(query(element, 'miles'), '40');
    change(query(element, 'field'), 'OtherAddress');
    expect(changed.mock.calls.pop()[0].detail.radius).toMatchObject({
      field: 'OtherAddress',
      miles: 40
    });

    query(element, 'remove').click();
    expect(changed.mock.calls.pop()[0].detail).toEqual({ radius: undefined, valid: true });
  });

  it('shows why a place was refused and keeps the query waiting', async () => {
    resolveRadiusCenter.mockRejectedValue({ body: { message: 'Not a US postal code.' } });
    const element = await mount();
    query(element, 'add').click();
    await flush();

    change(query(element, 'place'), '99999');
    query(element, 'use').click();
    await flush();

    expect(query(element, 'radius-error').textContent).toBe('Not a US postal code.');
    expect(query(element, 'center')).toBeNull();
  });

  it('shows a stand in note, and loads a saved radius without asking again', async () => {
    resolveRadiusCenter.mockResolvedValue({
      latitude: 1,
      longitude: 2,
      label: 'Postal code 02134',
      note: 'No geocode, used the postal code.'
    });
    const element = await mount();
    query(element, 'add').click();
    await flush();
    query(element, 'use').click();
    await flush();
    expect(query(element, 'center-note').textContent).toContain('No geocode');

    element.radius = { field: 'OtherAddress', miles: 10, latitude: 30.5, longitude: -90.25 };
    await flush();
    expect(query(element, 'field').value).toBe('OtherAddress');
    expect(query(element, 'center').textContent).toContain('30.5000, -90.2500');
  });

  it('offers nothing when the object has no address field', async () => {
    listRadiusFields.mockResolvedValue([]);
    const element = await mount();

    expect(query(element, 'no-fields')).not.toBeNull();
    expect(query(element, 'add')).toBeNull();
  });
});
