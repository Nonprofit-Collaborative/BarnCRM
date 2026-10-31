import { createElement } from 'lwc';
import ImportLoadOptions from 'c/importLoadOptions';

function render(properties = {}) {
  const element = createElement('c-import-load-options', { is: ImportLoadOptions });
  Object.assign(element, properties);
  document.body.appendChild(element);
  return element;
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

describe('what each row of a one-object mapping does', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('offers the four operations, each with what it risks', async () => {
    const element = render();
    await flush();
    const operation = element.shadowRoot.querySelector('[data-id="operation"]');
    expect(operation.options.map((option) => option.value)).toEqual([
      'Insert',
      'Update by record Id',
      'Update by a matching field',
      'Upsert by external ID'
    ]);
    expect(element.shadowRoot.querySelector('[data-id="operation-help"]').textContent).toContain(
      'c.Core_Import_LoadInsertHelp'
    );
    element.operation = 'Update by record Id';
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="operation-help"]').textContent).toContain(
      'c.Core_Import_LoadUpdateHelp'
    );
  });

  it('offers only the operations the object allows', async () => {
    const element = render({
      operation: 'Update by record Id',
      operations: ['Update by record Id']
    });
    await flush();
    const operation = element.shadowRoot.querySelector('[data-id="operation"]');
    expect(operation.options.map((option) => option.value)).toEqual(['Update by record Id']);
  });

  it('offers a delete only when the server does, and then asks nothing about lookups', async () => {
    const element = render({
      operations: ['Insert', 'Update by record Id', 'Upsert by external ID', 'Delete by record Id']
    });
    await flush();
    const operation = element.shadowRoot.querySelector('[data-id="operation"]');
    expect(operation.options.map((option) => option.value)).toContain('Delete by record Id');
    expect(element.shadowRoot.querySelector('[data-id="not-found"]')).not.toBeNull();
    element.operation = 'Delete by record Id';
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="operation-help"]').textContent).toContain(
      'c.Core_Import_LoadDeleteHelp'
    );
    expect(element.shadowRoot.querySelector('[data-id="not-found"]')).toBeNull();
  });

  it('asks for the external ID field only under an upsert', async () => {
    const element = render({
      keyFields: [{ value: 'Pair_Key__c', label: 'Pair Key' }]
    });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="match-field"]')).toBeNull();
    element.operation = 'Upsert by external ID';
    await flush();
    const field = element.shadowRoot.querySelector('[data-id="match-field"]');
    expect(field.options).toEqual([{ label: 'Pair Key', value: 'Pair_Key__c' }]);
  });

  it('says so when the object has no external ID field to upsert on', async () => {
    const element = render({ operation: 'Upsert by external ID', keyFields: [] });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="match-field"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="no-key-fields"]')).not.toBeNull();
  });

  it('offers any text, email or phone field under an update by a matching field', async () => {
    const element = render({
      operation: 'Update by a matching field',
      keyFields: [{ value: 'Pair_Key__c', label: 'Pair Key' }],
      rowMatchFields: [
        { value: 'Email__c', label: 'Email' },
        { value: 'Phone__c', label: 'Phone' }
      ]
    });
    await flush();
    const field = element.shadowRoot.querySelector('[data-id="match-field"]');
    expect(field.options).toEqual([
      { label: 'Email', value: 'Email__c' },
      { label: 'Phone', value: 'Phone__c' }
    ]);
    expect(element.shadowRoot.querySelector('[data-id="operation-help"]').textContent).toContain(
      'c.Core_Import_LoadUpdateByFieldHelp'
    );
  });

  it('says so when the object has no field an update can match on', async () => {
    const element = render({ operation: 'Update by a matching field', rowMatchFields: [] });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="match-field"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="no-key-fields"]').textContent).toContain(
      'c.Core_Import_LoadNoMatchFields'
    );
  });

  it('reports every change with all four choices', async () => {
    const element = render({ operation: 'Upsert by external ID', matchField: 'Pair_Key__c' });
    const changes = [];
    element.addEventListener('change', (event) => changes.push(event.detail));
    await flush();
    element.shadowRoot
      .querySelector('[data-id="not-found"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Leave it empty' } }));
    element.shadowRoot
      .querySelector('[data-id="operation"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Insert' } }));
    expect(changes).toEqual([
      {
        operation: 'Upsert by external ID',
        matchField: 'Pair_Key__c',
        lookupNotFound: 'Leave it empty',
        related: ''
      },
      {
        operation: 'Insert',
        matchField: 'Pair_Key__c',
        lookupNotFound: 'Reject the row',
        related: ''
      }
    ]);
  });

  it('offers no related records to a template without them, and one of several asks less', async () => {
    const element = render({
      operation: 'Upsert by external ID',
      relatedOptions: [{ value: 'Session__c.Program__c', label: 'Session (Program)' }]
    });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="related"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="related-insert-help"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="not-found"]')).not.toBeNull();

    element.hideLookups = true;
    element.related = 'Session__c.Program__c';
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="not-found"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="related"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="operation"]')).not.toBeNull();
  });

  it('keeps related records of a template that has them under a key, and says why not under Insert', async () => {
    const element = render({
      related: 'Session__c.Program__c',
      relatedOptions: [{ value: 'Session__c.Program__c', label: 'Session (Program)' }]
    });
    const changes = [];
    element.addEventListener('change', (event) => changes.push(event.detail));
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="related"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="related-insert-help"]').textContent).toBe(
      'c.Core_Import_RelatedInsertHelp'
    );

    element.operation = 'Upsert by external ID';
    await flush();
    const related = element.shadowRoot.querySelector('[data-id="related"]');
    expect(related.options).toEqual([
      { label: 'c.Core_Import_RelatedNone', value: '' },
      { label: 'Session (Program)', value: 'Session__c.Program__c' }
    ]);
    related.dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Session__c.Program__c' } })
    );
    expect(changes[0].related).toBe('Session__c.Program__c');
    expect(element.shadowRoot.querySelector('[data-id="related-insert-help"]')).toBeNull();
  });

  it('explains what leaving a missing lookup empty risks', async () => {
    const element = render({ lookupNotFound: 'Leave it empty' });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="not-found-help"]').textContent).toContain(
      'c.Core_Import_LookupLeaveEmptyHelp'
    );
  });
});
