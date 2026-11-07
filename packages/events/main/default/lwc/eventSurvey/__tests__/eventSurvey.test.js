import { createElement } from 'lwc';
import EventSurvey from 'c/eventSurvey';
import getSurvey from '@salesforce/apex/EventSurveyController.getSurvey';
import saveForm from '@salesforce/apex/EventSurveyController.saveForm';

jest.mock('@salesforce/apex/EventSurveyController.getSurvey', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/EventSurveyController.saveForm', () => ({ default: jest.fn() }), {
  virtual: true
});

const EVENT_ID = 'a01000000000001AAA';
const FORM_ID = 'a0F000000000001AAA';
const DATA = {
  available: true,
  formKey: FORM_ID,
  forms: [{ key: FORM_ID, label: 'After the Event' }],
  questions: [
    { key: 'rating', label: 'How was it?', kind: 'number' },
    { key: 'comment', label: 'Anything else?', kind: 'textarea' }
  ],
  attended: 10,
  sent: 8,
  responses: [
    { id: 'r1', name: 'Sam Lee', answers: '{"rating":5,"comment":"Great"}' },
    { id: 'r2', name: 'Ray Cho', answers: '{"rating":3}' }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(data = DATA) {
  getSurvey.mockResolvedValue(data);
  const element = createElement('c-event-survey', { is: EventSurvey });
  element.recordId = EVENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);
const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];

describe('c-event-survey', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws nothing at all when no module keeps forms', async () => {
    const element = await render({ available: false, forms: [], responses: [] });
    expect(one(element, '[data-id="survey"]')).toBeNull();
  });

  it('summarises the answers once a survey is chosen', async () => {
    const element = await render();
    expect(getSurvey).toHaveBeenCalledWith({ eventId: EVENT_ID });
    expect(all(element, '[data-id="question"]')).toHaveLength(2);
    expect(one(element, '[data-id="average"]')).not.toBeNull();
    expect(all(element, '[data-id="text"]')).toHaveLength(1);
    expect(one(element, '[data-id="counts"]')).not.toBeNull();
  });

  it('offers the forms with a no-survey choice and saves a change', async () => {
    const element = await render({ ...DATA, formKey: '', responses: [] });
    const form = one(element, '[data-id="form"]');
    expect(form.options.map((option) => option.value)).toEqual(['', FORM_ID]);
    expect(one(element, '[data-id="save"]').disabled).toBe(true);
    expect(one(element, '[data-id="counts"]')).toBeNull();
    form.dispatchEvent(new CustomEvent('change', { detail: { value: FORM_ID } }));
    await flush();
    expect(one(element, '[data-id="save"]').disabled).toBe(false);
    saveForm.mockResolvedValue();
    one(element, '[data-id="save"]').click();
    await flush();
    expect(saveForm).toHaveBeenCalledWith({ eventId: EVENT_ID, formKey: FORM_ID });
    expect(getSurvey).toHaveBeenCalledTimes(2);
  });

  it('shows the empty state for a chosen survey nobody has answered', async () => {
    const element = await render({ ...DATA, responses: [] });
    expect(one(element, '[data-id="empty-state"]')).not.toBeNull();
  });

  it('keeps a chosen form that is no longer public in the list', async () => {
    const element = await render({ ...DATA, forms: [] });
    expect(one(element, '[data-id="form"]').options.map((option) => option.value)).toEqual([
      '',
      FORM_ID
    ]);
  });
});
