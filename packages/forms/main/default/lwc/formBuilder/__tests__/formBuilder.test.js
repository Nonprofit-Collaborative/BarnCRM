import { createElement } from 'lwc';
import FormBuilder from 'c/formBuilder';
import getBuilder from '@salesforce/apex/FormBuilderController.getBuilder';
import getObjects from '@salesforce/apex/FormBuilderController.getObjects';
import getFields from '@salesforce/apex/FormBuilderController.getFields';
import saveDraft from '@salesforce/apex/FormBuilderController.saveDraft';
import publish from '@salesforce/apex/FormBuilderController.publish';

jest.mock('@salesforce/apex/FormBuilderController.getBuilder', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormBuilderController.getObjects', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormBuilderController.getFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormBuilderController.saveDraft', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FormBuilderController.publish', () => ({ default: jest.fn() }), {
  virtual: true
});

const READY = JSON.stringify({
  schemaVersion: 1,
  steps: [
    {
      key: 'you',
      title: 'You',
      fields: [
        {
          key: 'last',
          label: 'Last Name',
          type: 'text',
          required: true,
          target: { record: 'person', field: 'LastName' }
        }
      ]
    }
  ],
  records: [{ key: 'person', kind: 'person' }]
});

function form(definition, extra = {}) {
  return {
    formId: 'a01000000000001',
    name: 'Interest',
    status: 'Draft',
    definition,
    publishedVersion: null,
    canEdit: true,
    ...extra
  };
}

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(view) {
  getBuilder.mockResolvedValue(view);
  const element = createElement('c-form-builder', { is: FormBuilder });
  element.recordId = 'a01000000000001';
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-form-builder', () => {
  beforeEach(() => {
    getObjects.mockResolvedValue([{ value: 'Affiliation__c', label: 'Affiliation' }]);
    getFields.mockResolvedValue([
      { value: 'LastName', label: 'Last Name', type: 'string' },
      { value: 'Email', label: 'Email', type: 'email' }
    ]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('opens a new form with one step and the problems to fix before publishing', async () => {
    const element = await render(form(null));

    expect(element.shadowRoot.querySelectorAll('[data-id="step"]')).toHaveLength(1);
    expect(find(element, 'problems')).not.toBeNull();
    expect(find(element, 'publish').disabled).toBe(true);
    expect(find(element, 'save').disabled).toBe(true);
    expect(getFields).toHaveBeenCalledWith({ objectName: 'Contact' });
  });

  it('adds a question, edits it, and saves the draft', async () => {
    const element = await render(form(READY));
    saveDraft.mockImplementation(({ definitionJson }) => Promise.resolve(form(definitionJson)));

    find(element, 'add-question').click();
    await flush();
    const label = find(element, 'question-label');
    label.dispatchEvent(new CustomEvent('change', { detail: { value: 'Email' } }));
    await flush();
    find(element, 'save').click();
    await flush();
    await flush();

    const saved = JSON.parse(saveDraft.mock.calls[0][0].definitionJson);
    expect(saved.steps[0].fields).toHaveLength(2);
    expect(saved.steps[0].fields[1].label).toBe('Email');
    expect(find(element, 'result').textContent).toBe('c.Forms_Builder_Saved');
  });

  it('publishes a form with nothing to fix and says which version is live', async () => {
    const element = await render(form(READY));
    publish.mockResolvedValue(form(READY, { status: 'Published', publishedVersion: 3 }));

    expect(find(element, 'problems')).toBeNull();
    find(element, 'publish').click();
    await flush();
    await flush();

    expect(publish).toHaveBeenCalledWith({
      formId: 'a01000000000001',
      definitionJson: expect.any(String)
    });
    expect(find(element, 'result').textContent).toBe('c.Forms_Builder_PublishedVersion');
  });

  it('shows a server refusal and keeps the draft on the page', async () => {
    const element = await render(form(READY));
    publish.mockRejectedValue({ body: { message: 'Contact has no field Nope__c.' } });

    find(element, 'publish').click();
    await flush();
    await flush();

    expect(find(element, 'error').querySelector('c-barn-notice').message).toBe(
      'Contact has no field Nope__c.'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="question"]')).toHaveLength(1);
  });

  it('sets a condition on a later step from an earlier question', async () => {
    const element = await render(form(READY));
    saveDraft.mockImplementation(({ definitionJson }) => Promise.resolve(form(definitionJson)));

    find(element, 'add-step').click();
    await flush();
    find(element, 'add-condition').click();
    await flush();
    const op = find(element, 'clause-op');
    op.dispatchEvent(new CustomEvent('change', { detail: { value: 'equals' } }));
    await flush();
    find(element, 'clause-value').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Lee' } })
    );
    await flush();
    find(element, 'save').click();
    await flush();

    const saved = JSON.parse(saveDraft.mock.calls[0][0].definitionJson);
    expect(saved.steps[1].showWhen).toEqual({
      all: [{ field: 'last', op: 'equals', value: 'Lee' }]
    });
  });

  it('adds a related record and links its lookup to the person', async () => {
    getFields.mockImplementation(({ objectName }) =>
      Promise.resolve(
        objectName === 'Affiliation__c'
          ? [{ value: 'Contact__c', label: 'Contact', type: 'reference' }]
          : [{ value: 'LastName', label: 'Last Name', type: 'string' }]
      )
    );
    const element = await render(form(READY));
    saveDraft.mockImplementation(({ definitionJson }) => Promise.resolve(form(definitionJson)));

    find(element, 'add-record').dispatchEvent(
      new CustomEvent('select', { detail: { value: 'related' } })
    );
    await flush();
    find(element, 'record-object').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Affiliation__c' } })
    );
    await flush();
    await flush();
    find(element, 'record-link').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'person' } })
    );
    await flush();
    find(element, 'save').click();
    await flush();

    const saved = JSON.parse(saveDraft.mock.calls[0][0].definitionJson);
    expect(saved.records[1]).toEqual({
      key: 'related1',
      kind: 'related',
      object: 'Affiliation__c',
      links: { Contact__c: 'person' }
    });
  });

  it('previews the draft in the Form Runner', async () => {
    const element = await render(form(READY));

    find(element, 'preview').click();
    await flush();

    const runner = find(element, 'preview-runner').querySelector('c-form-runner');
    expect(JSON.parse(runner.definition).steps[0].fields[0].key).toBe('last');
  });

  it('shows a form the person cannot change as read only', async () => {
    const element = await render(form(READY, { canEdit: false }));

    expect(find(element, 'read-only')).not.toBeNull();
    expect(find(element, 'save')).toBeNull();
    expect(find(element, 'add-step')).toBeNull();
  });
});
