import { createElement } from 'lwc';
import EventSessionRatings from 'c/eventSessionRatings';
import getSetup from '@salesforce/apex/EventSessionRatings.getSetup';
import saveForm from '@salesforce/apex/EventSessionRatings.saveForm';

jest.mock('@salesforce/apex/EventSessionRatings.getSetup', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventSessionRatings.saveForm', () => ({ default: jest.fn() }), {
  virtual: true
});

const EVENT_ID = 'a01000000000001AAA';
const SETUP = {
  available: true,
  formKey: 'a0F000000000001AAA',
  forms: [{ key: 'a0F000000000001AAA', label: 'Session Rating' }],
  links: { s1: 'https://example.org/FormsPublic?form=f&record=s1' }
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(setup = SETUP) {
  getSetup.mockResolvedValue(setup);
  const element = createElement('c-event-session-ratings', { is: EventSessionRatings });
  element.recordId = EVENT_ID;
  element.sessions = [{ id: 's1', name: 'Talk A' }];
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-event-session-ratings', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows nothing without Forms', async () => {
    const element = await render({ available: false, forms: [], links: {} });
    expect(one(element, '[data-id="toggle"]')).toBeNull();
  });

  it('opens the panel with the chosen form and saves a new choice', async () => {
    const element = await render();
    one(element, '[data-id="toggle"]').click();
    await flush();
    const picker = one(element, '[data-id="form"]');
    expect(picker.value).toBe('a0F000000000001AAA');
    expect(picker.options).toHaveLength(2);
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: '' } }));
    saveForm.mockResolvedValue();
    one(element, '[data-id="save"]').click();
    await flush();
    expect(saveForm).toHaveBeenCalledWith({ eventId: EVENT_ID, formKey: '' });
    expect(getSetup).toHaveBeenCalledTimes(2);
  });
});
