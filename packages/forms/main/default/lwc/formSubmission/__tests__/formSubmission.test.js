// The GraphQL and object info test wire adapters are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import FormSubmission from 'c/formSubmission';
import { graphql } from 'lightning/graphql';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import processAgain from '@salesforce/apex/FormSubmissionController.processAgain';

jest.mock(
  '@salesforce/apex/FormSubmissionController.processAgain',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

const DEFINITION = JSON.stringify({
  schemaVersion: 1,
  steps: [
    {
      key: 'you',
      fields: [
        { key: 'last', label: 'Last Name', type: 'text' },
        {
          key: 'role',
          label: 'Role',
          type: 'picklist',
          options: [{ value: 'vol', label: 'Volunteer' }]
        }
      ]
    }
  ]
});

/** A submission as the GraphQL wire returns it. */
function node({ status, message = null, outcome = null, formName = 'Volunteer Interest' }) {
  return {
    Id: 'a03000000000001',
    Form_Name__c: { value: 'Stored Name' },
    Form_Version__c: { value: 'a02000000000001' },
    Status__c: { value: status },
    Message__c: { value: message },
    Answers__c: { value: JSON.stringify({ role: 'vol', last: 'Lee' }) },
    Outcome__c: { value: outcome },
    Form__r: formName ? { Name: { value: formName } } : null,
    Form_Version__r: { Definition__c: { value: DEFINITION } }
  };
}

const HELD = node({
  status: 'Needs Review',
  message: 'More than one person matches these answers.'
});

const DONE = node({
  status: 'Processed',
  outcome: JSON.stringify([
    {
      key: 'person',
      kind: 'person',
      objectName: 'Contact',
      recordId: '003000000000001',
      action: 'updated'
    }
  ])
});

const result = (record) => ({
  uiapi: { query: { Form_Submission__c: { edges: record ? [{ node: record }] : [] } } }
});

async function render(record = HELD, refresh) {
  const element = createElement('c-form-submission', { is: FormSubmission });
  element.recordId = 'a03000000000001';
  document.body.appendChild(element);
  getObjectInfo.emit({ apiName: 'Form_Submission__c', updateable: true });
  graphql.emit(result(record), undefined, refresh);
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

  it('reads the submission it sits on as the person', async () => {
    await render();
    expect(graphql.getLastConfig().variables).toEqual({ submissionId: 'a03000000000001' });
  });

  it('shows the answers by question and why a held one waits', async () => {
    const element = await render();

    const terms = [...find(element, 'answers').querySelectorAll('dt')].map((dt) => dt.textContent);
    expect(terms).toEqual(['Last Name', 'Role']);
    expect(find(element, 'answers').textContent).toContain('Volunteer');
    expect(find(element, 'message').querySelector('c-barn-notice').message).toBe(
      'More than one person matches these answers.'
    );
    expect(find(element, 'process-again')).not.toBeNull();
    expect(find(element, 'records')).toBeNull();
  });

  it('offers Process Again only to someone who may edit the submission', async () => {
    const element = await render();
    getObjectInfo.emit({ apiName: 'Form_Submission__c', updateable: false });
    await flush();
    expect(find(element, 'process-again')).toBeNull();
  });

  it('processes a held one again and shows what it wrote', async () => {
    processAgain.mockResolvedValue({ status: 'Processed' });
    const refresh = jest.fn(() => {
      graphql.emit(result(DONE), undefined, refresh);
      return Promise.resolve();
    });
    const element = await render(HELD, refresh);

    find(element, 'process-again').click();
    await flush();
    await flush();

    expect(processAgain).toHaveBeenCalledWith({ submissionId: 'a03000000000001' });
    expect(refresh).toHaveBeenCalled();
    expect(find(element, 'result').textContent).toBe('c.Forms_Runner_Processed');
    const link = find(element, 'records').querySelector('a');
    expect(link.getAttribute('href')).toBe('/lightning/r/003000000000001/view');
    expect(find(element, 'records').textContent).toContain('c.Forms_Written_updated');
    expect(find(element, 'process-again')).toBeNull();
  });

  it('shows a refusal from the server', async () => {
    processAgain.mockRejectedValue({ body: { message: 'Already processed.' } });
    const element = await render();

    find(element, 'process-again').click();
    await flush();
    await flush();

    expect(find(element, 'error').querySelector('c-barn-notice').message).toBe(
      'Already processed.'
    );
  });

  it('says when the submission cannot be read, and shows nothing for none', async () => {
    const element = createElement('c-form-submission', { is: FormSubmission });
    element.recordId = 'a03000000000001';
    document.body.appendChild(element);
    graphql.emitErrors([{ message: 'No access' }]);
    await flush();
    expect(find(element, 'error').querySelector('c-barn-notice').message).toBe('No access');

    const empty = await render(null);
    expect(find(empty, 'status')).toBeNull();
  });
});
