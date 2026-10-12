import { createElement } from 'lwc';
import CustomMetadataManager from 'c/customMetadataManager';
import getTypes from '@salesforce/apex/CustomMetadataManagerController.getTypes';
import saveRow from '@salesforce/apex/CustomMetadataManagerController.saveRow';
import setArchived from '@salesforce/apex/CustomMetadataManagerController.setArchived';
import getOutcome from '@salesforce/apex/CustomMetadataManagerController.getOutcome';

jest.mock(
  '@salesforce/apex/CustomMetadataManagerController.getTypes',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/CustomMetadataManagerController.saveRow',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/CustomMetadataManagerController.setArchived',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/CustomMetadataManagerController.getOutcome',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const TYPE = 'Relationship_Type__mdt';
const JOB = '0Af000000000001AAA';

function types(ownRows = true) {
  const rows = [
    {
      developerName: 'Spouse',
      label: 'Spouse',
      shipped: true,
      archived: false,
      values: { Type__c: 'Spouse', Reciprocal_Type__c: 'Spouse', Description__c: null }
    }
  ];
  if (ownRows) {
    rows.push({
      developerName: 'Org_Mentor',
      label: 'Mentor',
      shipped: false,
      archived: false,
      values: { Type__c: 'Mentor', Reciprocal_Type__c: 'Mentee', Description__c: null }
    });
  }
  const choices = [
    { label: 'Mentor', value: 'Mentor' },
    { label: 'Mentee', value: 'Mentee' }
  ];
  return [
    {
      typeName: TYPE,
      label: 'Relationship types',
      help: 'What the other side becomes.',
      fields: [
        { apiName: 'Type__c', label: 'Type', required: true, isLong: false, choices },
        { apiName: 'Reciprocal_Type__c', label: 'Reciprocal Type', required: true, choices },
        { apiName: 'Description__c', label: 'Description', required: false, isLong: true }
      ],
      rows
    }
  ];
}

async function flush() {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function build() {
  const element = createElement('c-custom-metadata-manager', { is: CustomMetadataManager });
  document.body.appendChild(element);
  await flush();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function change(target, value) {
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

async function fillAndSave(element) {
  find(element, 'add').click();
  await flush();
  change(find(element, 'name'), 'Mentee');
  const [type, reciprocal] = element.shadowRoot.querySelectorAll('lightning-combobox');
  change(type, 'Mentee');
  change(reciprocal, 'Mentor');
  await flush();
  find(element, 'save').click();
  await flush();
}

describe('c-custom-metadata-manager', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    getTypes.mockResolvedValue(types());
    saveRow.mockResolvedValue(JOB);
    setArchived.mockResolvedValue(JOB);
    getOutcome.mockResolvedValue({ status: 'Succeeded' });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it('lists the organization rows apart from the shipped ones, which have no actions', async () => {
    const element = await build();

    const own = find(element, 'own-rows');
    const shipped = find(element, 'shipped-rows');
    expect(own.data.map((row) => row.developerName)).toEqual(['Org_Mentor']);
    expect(shipped.data.map((row) => row.developerName)).toEqual(['Spouse']);
    expect(own.columns.some((column) => column.type === 'action')).toBe(true);
    expect(shipped.columns.some((column) => column.type === 'action')).toBe(false);
    expect(own.data[0].statusText).toBe('c.Core_CmdtManager_StatusInUse');
  });

  it('says when nothing has been added yet', async () => {
    getTypes.mockResolvedValue(types(false));
    const element = await build();

    expect(find(element, 'own-rows')).toBeNull();
    expect(find(element, 'own-empty')).not.toBeNull();
  });

  it('adds a row, waits for the deployment, and reloads the list', async () => {
    const element = await build();

    await fillAndSave(element);

    expect(saveRow).toHaveBeenCalledWith({
      typeName: TYPE,
      input: {
        developerName: null,
        label: 'Mentee',
        values: { Type__c: 'Mentee', Reciprocal_Type__c: 'Mentor', Description__c: '' }
      }
    });
    expect(find(element, 'status').textContent).toBe('c.Core_CmdtManager_Saving');
    expect(find(element, 'form')).toBeNull();

    jest.advanceTimersByTime(3000);
    await flush();

    expect(getOutcome).toHaveBeenCalledWith({ deploymentId: JOB });
    expect(find(element, 'status').textContent).toBe('c.Core_CmdtManager_Saved');
    expect(getTypes).toHaveBeenCalledTimes(2);
  });

  it('shows why a deployment failed', async () => {
    getOutcome.mockResolvedValue({
      status: 'Failed',
      message: 'The change to Mentee was not saved.'
    });
    const element = await build();

    await fillAndSave(element);
    jest.advanceTimersByTime(3000);
    await flush();

    expect(find(element, 'error').textContent).toBe('The change to Mentee was not saved.');
  });

  it('keeps the form open and shows a refusal from Apex', async () => {
    saveRow.mockRejectedValue({ body: { message: 'Mentee is not a choice.' } });
    const element = await build();

    await fillAndSave(element);

    expect(find(element, 'error').textContent).toBe('Mentee is not a choice.');
    expect(find(element, 'form')).not.toBeNull();
    expect(getOutcome).not.toHaveBeenCalled();
  });

  it('says it is still saving when a minute passes with no outcome', async () => {
    getOutcome.mockResolvedValue({ status: 'Pending' });
    const element = await build();

    await fillAndSave(element);
    for (let i = 0; i < 20; i++) {
      jest.advanceTimersByTime(3000);
      // eslint-disable-next-line no-await-in-loop
      await flush();
    }

    expect(getOutcome).toHaveBeenCalledTimes(20);
    expect(find(element, 'status').textContent).toBe('c.Core_CmdtManager_StillSaving');
  });

  it('archives and restores through row actions, and edits with the row filled in', async () => {
    const element = await build();
    const own = find(element, 'own-rows');
    const mentor = own.data[0];

    own.dispatchEvent(
      new CustomEvent('rowaction', { detail: { action: { name: 'archive' }, row: mentor } })
    );
    await flush();
    expect(setArchived).toHaveBeenCalledWith({
      typeName: TYPE,
      developerName: 'Org_Mentor',
      archived: true
    });

    jest.advanceTimersByTime(3000);
    await flush();
    own.dispatchEvent(
      new CustomEvent('rowaction', { detail: { action: { name: 'restore' }, row: mentor } })
    );
    await flush();
    expect(setArchived).toHaveBeenLastCalledWith({
      typeName: TYPE,
      developerName: 'Org_Mentor',
      archived: false
    });

    own.dispatchEvent(
      new CustomEvent('rowaction', { detail: { action: { name: 'edit' }, row: mentor } })
    );
    await flush();
    expect(find(element, 'name').value).toBe('Mentor');
    expect(element.shadowRoot.querySelector('lightning-combobox').value).toBe('Mentor');
  });

  it('offers Archive on a row in use and Restore on an archived one', async () => {
    const element = await build();
    const own = find(element, 'own-rows');
    const actions = own.columns.find((column) => column.type === 'action');
    const offered = jest.fn();

    actions.typeAttributes.rowActions({ archived: false }, offered);
    actions.typeAttributes.rowActions({ archived: true }, offered);

    expect(offered.mock.calls[0][0].map((action) => action.name)).toEqual(['edit', 'archive']);
    expect(offered.mock.calls[1][0].map((action) => action.name)).toEqual(['edit', 'restore']);
  });

  it('shows a load failure in words', async () => {
    getTypes.mockRejectedValue({});
    const element = await build();

    expect(find(element, 'error').textContent).toBe('c.Core_CmdtManager_LoadError');
  });
});
