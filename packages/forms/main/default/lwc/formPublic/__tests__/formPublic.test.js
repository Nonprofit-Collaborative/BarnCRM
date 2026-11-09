import { createElement } from 'lwc';
import FormPublic from 'c/formPublic';
import getForm from '@salesforce/apex/FormPublicController.getForm';
import submit from '@salesforce/apex/FormPublicController.submit';
import saveDraft from '@salesforce/apex/FormPublicController.saveDraft';

jest.mock('@salesforce/apex/FormPublicController.getForm', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormPublicController.saveDraft', () => ({ default: jest.fn() }), {
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
    expect(getForm).toHaveBeenCalledWith({ formId: FORM.formId, resumeToken: null });
    expect(find(element, '[data-id="save-open"]')).toBeNull();

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
      contextRecordId: 'a05000000000001',
      filesJson: '{}',
      resumeToken: null
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

  it('sends a chosen file beside the answers, and refuses files that are too large', async () => {
    const withFile = JSON.stringify({
      schemaVersion: 1,
      steps: [
        {
          key: 'you',
          fields: [
            { key: 'last', label: 'Last Name', type: 'text', required: true },
            { key: 'cv', label: 'Resume', type: 'file' }
          ]
        }
      ],
      public: { enabled: true }
    });
    getForm.mockResolvedValue({ ...FORM, definition: withFile });
    submit.mockResolvedValue({ status: 'Received' });
    const element = await render({ formId: FORM.formId });
    answer(element, 'last', 'Zzpublic');
    const big = new File(['x'], 'big.pdf', { type: 'application/pdf' });
    Object.defineProperty(big, 'size', { value: 2 * 1024 * 1024 });
    find(element, '[data-key="cv"]').dispatchEvent(
      new CustomEvent('change', { detail: { files: [big] } })
    );
    await flush();
    expect(find(element, '[data-id="file-name"]').textContent).toBe('big.pdf');
    find(element, '[data-id="submit"]').click();
    await flush();
    expect(submit).not.toHaveBeenCalled();
    expect(find(element, '[data-id="answer-problem"]')).not.toBeNull();

    const small = new File(['hello'], 'cv.pdf', { type: 'application/pdf' });
    find(element, '[data-key="cv"]').dispatchEvent(
      new CustomEvent('change', { detail: { files: [small] } })
    );
    find(element, '[data-id="submit"]').click();
    await flush();
    await flush();
    await flush();
    const sent = submit.mock.calls[0][0];
    expect(JSON.parse(sent.answersJson)).toEqual({ last: 'Zzpublic', cv: 'cv.pdf' });
    expect(JSON.parse(sent.filesJson)).toEqual({ cv: { name: 'cv.pdf', data: btoa('hello') } });
  });

  it('saves the answers for later and opens them again from the emailed link', async () => {
    getForm.mockResolvedValue({ ...FORM, canSave: true });
    saveDraft.mockResolvedValueOnce({ status: 'Invalid', problems: { saveForLater: 'badEmail' } });
    saveDraft.mockResolvedValueOnce({ status: 'Saved' });
    const element = await render({ formId: FORM.formId });
    answer(element, 'last', 'Zzlater');
    find(element, '[data-id="save-open"]').click();
    await flush();
    find(element, '[data-id="save-email"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'nope' } })
    );
    find(element, '[data-id="save-send"]').click();
    await flush();
    await flush();
    expect(find(element, '[data-id="save-problem"]')).not.toBeNull();
    find(element, '[data-id="save-send"]').click();
    await flush();
    await flush();
    expect(saveDraft).toHaveBeenLastCalledWith({
      ticket: FORM.ticket,
      answersJson: JSON.stringify({ last: 'Zzlater' }),
      trap: '',
      email: 'nope',
      step: 0
    });
    expect(find(element, '[data-id="outcome"]')).not.toBeNull();
    expect(find(element, '[data-id="submit"]')).toBeNull();

    document.body.removeChild(element);
    getForm.mockResolvedValue({ ...FORM, answers: '{"last":"Zzlater"}', step: 0 });
    submit.mockResolvedValue({ status: 'Received' });
    const resumed = await render({ formId: FORM.formId, resumeToken: 'tok' });
    expect(getForm).toHaveBeenLastCalledWith({ formId: FORM.formId, resumeToken: 'tok' });
    expect(find(resumed, '[data-id="notice"]')).not.toBeNull();
    find(resumed, '[data-id="submit"]').click();
    await flush();
    await flush();
    expect(submit.mock.calls[0][0].resumeToken).toBe('tok');
  });

  it('opens a fresh form when the emailed link no longer works', async () => {
    getForm.mockResolvedValueOnce(null);
    getForm.mockResolvedValueOnce(FORM);
    const element = await render({ formId: FORM.formId, resumeToken: 'gone' });
    await flush();
    expect(getForm).toHaveBeenLastCalledWith({ formId: FORM.formId, resumeToken: null });
    expect(find(element, '[data-id="notice"]')).not.toBeNull();
    expect(find(element, '[data-id="title"]')).not.toBeNull();
  });

  it('says the form is not open when it is not public', async () => {
    getForm.mockResolvedValue(null);
    const element = await render({ formId: 'a01000000000009' });
    expect(find(element, '[data-id="closed"]')).not.toBeNull();
    expect(find(element, '[data-id="title"]')).toBeNull();
  });

  it('is the page with an h1 on its own, and a section with an h3 inside a public page', async () => {
    getForm.mockResolvedValue(FORM);
    const alone = await render({ formId: FORM.formId });
    expect(find(alone, '[data-id="title"]').tagName).toBe('H1');
    expect(find(alone, 'main')).toBeNull();

    const inside = await render({ formId: FORM.formId, embedded: true });
    expect(find(inside, '[data-id="title"]').tagName).toBe('H3');
  });
});
