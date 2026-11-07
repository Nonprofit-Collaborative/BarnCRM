import { createElement } from 'lwc';
import FormRunner from 'c/formRunner';
import getPublishedForms from '@salesforce/apex/FormRunnerController.getPublishedForms';
import getForm from '@salesforce/apex/FormRunnerController.getForm';
import submit from '@salesforce/apex/FormRunnerController.submit';

jest.mock(
  '@salesforce/apex/FormRunnerController.getPublishedForms',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/FormRunnerController.getForm', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormRunnerController.submit', () => ({ default: jest.fn() }), {
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
        { key: 'age', label: 'Age', type: 'number' }
      ]
    },
    {
      key: 'guardian',
      title: 'Guardian',
      showWhen: { all: [{ field: 'age', op: 'lessThan', value: 18 }] },
      fields: [{ key: 'guardian', label: 'Guardian', type: 'text', required: true }]
    },
    {
      key: 'more',
      title: 'More',
      fields: [{ key: 'why', label: 'Why', type: 'textarea' }]
    }
  ],
  records: [{ key: 'person', kind: 'person' }]
});

const FORM = {
  formId: 'a01000000000001',
  name: 'Volunteer Interest',
  status: 'Published',
  version: 1,
  definition: DEFINITION,
  canSubmit: true
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const find = (element, selector) => element.shadowRoot.querySelector(selector);

async function render(props) {
  const element = createElement('c-form-runner', { is: FormRunner });
  Object.assign(element, props);
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

function answer(element, key, value) {
  const input = find(element, `[data-key="${key}"]`);
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-form-runner', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('opens the form whose page it is on, with no record to fill in from', async () => {
    getForm.mockResolvedValue(FORM);
    await render({ recordId: 'a01000000000001', objectApiName: 'Form__c' });

    expect(getForm).toHaveBeenCalledWith({ formId: 'a01000000000001', contextRecordId: null });
  });

  it('asks for a fix before going on, then skips a step its condition hides', async () => {
    getForm.mockResolvedValue(FORM);
    const element = await render({ formId: 'a01000000000001' });

    find(element, '[data-id="next"]').click();
    await flush();
    expect(find(element, '[data-id="answer-problem"]').textContent).toBe('c.Forms_Answer_required');

    answer(element, 'last', 'Lee');
    answer(element, 'age', '30');
    await flush();
    find(element, '[data-id="next"]').click();
    await flush();

    expect(find(element, '[data-key="why"]')).not.toBeNull();
    expect(find(element, '[data-key="guardian"]')).toBeNull();
    expect(find(element, 'c-barn-step-flow').steps.map((step) => step.label)).toEqual([
      'You',
      'More'
    ]);
  });

  it('sends only the answers that count, with the record it is filled in from', async () => {
    getForm.mockResolvedValue(FORM);
    submit.mockResolvedValue({ submissionId: 'a03000000000001', status: 'Processed' });
    const element = await render({ recordId: '001000000000001', objectApiName: 'Account' });

    answer(element, 'last', ' Lee ');
    answer(element, 'age', '30');
    await flush();
    find(element, '[data-id="next"]').click();
    await flush();
    find(element, '[data-id="submit"]').click();
    await flush();
    await flush();

    expect(submit).toHaveBeenCalledWith({
      formId: 'a01000000000001',
      answersJson: JSON.stringify({ last: 'Lee', age: 30 }),
      contextRecordId: '001000000000001'
    });
    expect(find(element, '[data-id="outcome"] c-barn-notice').message).toBe(
      'c.Forms_Runner_Processed'
    );
  });

  it('goes back to an answer the server refused', async () => {
    getForm.mockResolvedValue(FORM);
    submit.mockResolvedValue({ status: 'Invalid', problems: { last: 'tooLong' } });
    const element = await render({ formId: 'a01000000000001' });

    answer(element, 'last', 'Lee');
    await flush();
    find(element, '[data-id="next"]').click();
    await flush();
    find(element, '[data-id="submit"]').click();
    await flush();
    await flush();

    expect(find(element, '[data-key="last"]')).not.toBeNull();
    expect(find(element, '[data-id="answer-problem"]').textContent).toBe('c.Forms_Answer_tooLong');
  });

  it('previews a definition and never sends it', async () => {
    const element = await render({ definition: DEFINITION });

    expect(find(element, '[data-id="preview-note"]')).not.toBeNull();
    answer(element, 'last', 'Lee');
    await flush();
    find(element, '[data-id="next"]').click();
    await flush();
    expect(find(element, '[data-id="submit"]').disabled).toBe(true);
    expect(getForm).not.toHaveBeenCalled();
  });

  it('offers the published forms when none is set', async () => {
    getForm.mockResolvedValue(FORM);
    const element = await render({});
    getPublishedForms.emit([{ id: 'a01000000000001', name: 'Volunteer Interest' }]);
    await flush();

    const picker = find(element, '[data-id="picker"]');
    expect(picker.options).toEqual([{ value: 'a01000000000001', label: 'Volunteer Interest' }]);
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'a01000000000001' } }));
    await flush();
    await flush();

    expect(getForm).toHaveBeenCalledWith({ formId: 'a01000000000001', contextRecordId: null });
    expect(find(element, '[data-key="last"]')).not.toBeNull();
  });
});
