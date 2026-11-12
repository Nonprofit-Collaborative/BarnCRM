import { createElement } from 'lwc';
import FormPublicPage from 'c/formPublicPage';
import getPage from '@salesforce/apex/FormPublicController.getPage';
import listPages from '@salesforce/apex/FormPublicController.listPages';
import getForm from '@salesforce/apex/FormPublicController.getForm';

jest.mock('@salesforce/apex/FormPublicController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormPublicController.listPages', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormPublicController.getForm', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormPublicController.submit', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormPublicController.saveDraft', () => ({ default: jest.fn() }), {
  virtual: true
});

const PAGE = {
  kind: 'events',
  title: 'Spring Gala',
  description: 'An evening at the grange.',
  start: '2026-12-05T23:00:00.000Z',
  end: '2026-12-06T03:00:00.000Z',
  timeZone: 'UTC',
  facts: [{ label: 'Where', value: 'Grange Hall' }],
  sections: [
    {
      key: 'tickets',
      title: 'Tickets',
      items: [{ title: 'General', amount: 50, currency: 'USD', note: 'Pay at the door.' }]
    }
  ],
  registration: 'Open',
  formId: 'a0B000000000001AAA',
  message: 'Register below.'
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const find = (element, selector) => element.shadowRoot.querySelector(selector);
const findAll = (element, selector) => element.shadowRoot.querySelectorAll(selector);

async function render(props) {
  const element = createElement('c-form-public-page', { is: FormPublicPage });
  Object.assign(element, props);
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

describe('c-form-public-page', () => {
  beforeEach(() => {
    getForm.mockResolvedValue(null);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the published page and the form while registration is open', async () => {
    getPage.mockResolvedValue(JSON.stringify(PAGE));
    const element = await render({ recordId: 'a01000000000001' });

    expect(getPage).toHaveBeenCalledWith({ recordId: 'a01000000000001' });
    expect(document.title).toBe('Spring Gala');
    expect(find(element, '[data-id="title"]').textContent).toContain('Spring Gala');
    expect(find(element, '[data-id="price"]').textContent).toBe('$50.00');
    expect(find(element, '[data-id="note"]').textContent).toBe('Pay at the door.');
    expect(find(element, '[data-id="message"]').textContent).toBe('Register below.');
    const form = find(element, 'c-form-public');
    expect(form).not.toBeNull();
    expect(form.formId).toBe(PAGE.formId);
    expect(form.recordId).toBe('a01000000000001');
  });

  it('shows no form when registration is closed', async () => {
    getPage.mockResolvedValue(
      JSON.stringify({ ...PAGE, registration: 'Closed', message: 'Closed.' })
    );
    const element = await render({ recordId: 'a01000000000001' });

    expect(find(element, 'c-form-public')).toBeNull();
    expect(find(element, '[data-id="message"]').textContent).toBe('Closed.');
  });

  it('says the page is missing when nothing is published or loading fails', async () => {
    getPage.mockResolvedValue(null);
    let element = await render({ recordId: 'a01000000000001' });
    expect(find(element, '[data-id="missing"]')).not.toBeNull();

    document.body.removeChild(element);
    getPage.mockRejectedValue(new Error('down'));
    element = await render({ recordId: 'a01000000000001' });
    expect(find(element, '[data-id="missing"]')).not.toBeNull();
  });

  it('lists published pages with links', async () => {
    listPages.mockResolvedValue(
      JSON.stringify({
        title: 'Upcoming Events',
        empty: 'None right now.',
        timeZone: 'UTC',
        items: [{ recordId: 'a01', title: 'Spring Gala', start: PAGE.start }]
      })
    );
    const element = await render({ listKind: 'events' });

    expect(document.title).toBe('Upcoming Events');
    expect(listPages).toHaveBeenCalledWith({ kind: 'events' });
    const links = findAll(element, '[data-id="list-item"] a');
    expect(links).toHaveLength(1);
    expect(links[0].getAttribute('href')).toBe('FormsPublic?record=a01');
    expect(find(element, '[data-id="list-empty"]')).toBeNull();
  });

  it('says when the list is empty', async () => {
    listPages.mockResolvedValue(
      JSON.stringify({ title: 'Upcoming Events', empty: 'None right now.', items: [] })
    );
    const element = await render({ listKind: 'events' });
    expect(find(element, '[data-id="list-empty"]').textContent).toBe('None right now.');
  });

  it('says a payment is being confirmed on return from checkout, under the page form title', async () => {
    getPage.mockResolvedValue(JSON.stringify({ ...PAGE, kind: 'appeals', formTitle: 'Give Now' }));
    const element = await render({ recordId: 'a01000000000001', payment: 'done' });

    expect(find(element, '[data-id="payment"] c-barn-notice').variant).toBe('success');
    expect(find(element, '[data-id="registration"] h2').textContent).toBe('Give Now');
  });

  it('says a cancelled payment charged nothing, and shows no notice otherwise', async () => {
    getPage.mockResolvedValue(JSON.stringify(PAGE));
    const cancelled = await render({ recordId: 'a01000000000001', payment: 'cancelled' });
    expect(find(cancelled, '[data-id="payment"] c-barn-notice').variant).toBe('info');

    const plain = await render({ recordId: 'a01000000000001', payment: 'other' });
    expect(find(plain, '[data-id="payment"]')).toBeNull();
  });
});
