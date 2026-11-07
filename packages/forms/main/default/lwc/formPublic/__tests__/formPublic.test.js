import { createElement } from 'lwc';
import FormPublic from 'c/formPublic';
import getForm from '@salesforce/apex/FormPublicController.getForm';
import submit from '@salesforce/apex/FormPublicController.submit';

jest.mock('@salesforce/apex/FormPublicController.getForm', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormPublicController.submit', () => ({ default: jest.fn() }), {
  virtual: true
});

const DEFINITION = JSON.stringify({
  schemaVersion: 1,
  steps: [
    {
      key: 'you',
      title: 'You',
      fields: [
        { key: 'last', label: 'Last Name', type: 'text', required: true },
        { key: 'email', label: 'Email', type: 'email' }
      ]
    }
  ],
  public: { enabled: true }
});

const FORM = {
  formId: 'a01000000000001',
  name: 'Volunteer Sign-Up',
  description: 'Tell us about you.',
  version: 2,
  definition: DEFINITION,
  ticket: 'a02000000000001:1700000000000:sig'
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const find = (element, selector) => element.shadowRoot.querySelector(selector);

async function render(props) {
  const element = createElement('c-form-public', { is: FormPublic });
  Object.assign(element, props);
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

function answer(element, key, value) {
  find(element, `[data-key="${key}"]`).dispatchEvent(
    new CustomEvent('change', { detail: { value } })
  );
}

describe('c-form-public', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the form and sends the answers with the ticket and the empty hidden question', async () => {
    getForm.mockResolvedValue(FORM);
    submit.mockResolvedValue({ status: 'Received', message: 'Thanks!' });
    const element = await render({ formId: FORM.formId, recordId: 'a05000000000001' });
    expect(find(element, '[data-id="title"]').textContent).toBe('Volunteer Sign-Up');
    expect(getForm).toHaveBeenCalledWith({ formId: FORM.formId });

    find(element, '[data-id="submit"]').click();
    await flush();
    expect(submit).not.toHaveBeenCalled();
    expect(find(element, '[data-id="answer-problem"]')).not.toBeNull();

    answer(element, 'last', 'Zzpublic');
    find(element, '[data-id="submit"]').click();
    await flush();
    await flush();
    expect(submit).toHaveBeenCalledWith({
      ticket: FORM.ticket,
      answersJson: JSON.stringify({ last: 'Zzpublic' }),
      trap: '',
      contextRecordId: 'a05000000000001'
    });
    expect(find(element, '[data-id="outcome"] c-barn-notice').message).toBe('Thanks!');
    expect(find(element, '[data-id="submit"]')).toBeNull();
  });

  it('keeps the form open when asked to send again, and shows refused answers', async () => {
    getForm.mockResolvedValue(FORM);
    submit.mockResolvedValueOnce({ status: 'Retry' });
    submit.mockResolvedValueOnce({ status: 'Invalid', problems: { email: 'badEmail' } });
    const element = await render({ formId: FORM.formId });
    answer(element, 'last', 'Zzpublic');
    find(element, '[data-id="submit"]').click();
    await flush();
    await flush();
    expect(find(element, '[data-id="outcome"]')).not.toBeNull();
    expect(find(element, '[data-id="submit"]')).not.toBeNull();

    find(element, '[data-id="submit"]').click();
    await flush();
    await flush();
    expect(find(element, '[data-id="answer-problem"]')).not.toBeNull();
  });

  it('says the form is not open when it is not public', async () => {
    getForm.mockResolvedValue(null);
    const element = await render({ formId: 'a01000000000009' });
    expect(find(element, '[data-id="closed"]')).not.toBeNull();
    expect(find(element, '[data-id="title"]')).toBeNull();
  });
});
