import { createElement } from 'lwc';
import FormSubmission from 'c/formSubmission';
import getSubmission from '@salesforce/apex/FormSubmissionController.getSubmission';
import processAgain from '@salesforce/apex/FormSubmissionController.processAgain';

jest.mock(
  '@salesforce/apex/FormSubmissionController.getSubmission',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/FormSubmissionController.processAgain',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

const HELD = {
  id: 'a03000000000001',
  formName: 'Volunteer Interest',
  status: 'Needs Review',
  message: 'More than one person matches these answers.',
  canProcess: true,
  answers: [
    { key: 'last', label: 'Last Name', type: 'text', value: 'Lee' },
    { key: 'role', label: 'Role', type: 'picklist', value: 'Volunteer' }
  ],
  records: []
};

const DONE = {
  ...HELD,
  status: 'Processed',
  message: null,
  canProcess: false,
  records: [
    {
      key: 'person',
      kind: 'person',
      objectName: 'Contact',
      recordId: '003000000000001',
      action: 'updated'
    }
  ]
};

async function render() {
  const element = createElement('c-form-submission', { is: FormSubmission });
  element.recordId = 'a03000000000001';
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

describe('c-form-submission', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the answers by question and why a held one waits', async () => {
    getSubmission.mockResolvedValue(HELD);
    const element = await render();

    const terms = [...find(element, 'answers').querySelectorAll('dt')].map((dt) => dt.textContent);
    expect(terms).toEqual(['Last Name', 'Role']);
    expect(find(element, 'message').querySelector('c-barn-notice').message).toBe(HELD.message);
    expect(find(element, 'process-again')).not.toBeNull();
    expect(find(element, 'records')).toBeNull();
  });

  it('processes a held one again and shows what it wrote', async () => {
    getSubmission.mockResolvedValueOnce(HELD).mockResolvedValueOnce(DONE);
    processAgain.mockResolvedValue({ status: 'Processed' });
    const element = await render();

    find(element, 'process-again').click();
    await flush();
    await flush();

    expect(processAgain).toHaveBeenCalledWith({ submissionId: 'a03000000000001' });
    expect(find(element, 'result').textContent).toBe('c.Forms_Runner_Processed');
    const link = find(element, 'records').querySelector('a');
    expect(link.getAttribute('href')).toBe('/lightning/r/003000000000001/view');
    expect(find(element, 'records').textContent).toContain('c.Forms_Written_updated');
    expect(find(element, 'process-again')).toBeNull();
  });

  it('shows a refusal from the server', async () => {
    getSubmission.mockResolvedValue(HELD);
    processAgain.mockRejectedValue({ body: { message: 'Already processed.' } });
    const element = await render();

    find(element, 'process-again').click();
    await flush();
    await flush();

    expect(find(element, 'error').querySelector('c-barn-notice').message).toBe(
      'Already processed.'
    );
  });
});
