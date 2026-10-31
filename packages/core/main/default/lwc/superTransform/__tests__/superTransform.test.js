import { createElement } from 'lwc';
import SuperTransform from 'c/superTransform';
import BarnConfirmModal from 'c/barnConfirmModal';
import getPage from '@salesforce/apex/BulkUpdateController.getPage';
import getObjects from '@salesforce/apex/BulkUpdateController.getObjects';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';
import getCopySources from '@salesforce/apex/BulkUpdateController.getCopySources';
import countMatches from '@salesforce/apex/BulkUpdateController.countMatches';
import previewSample from '@salesforce/apex/BulkUpdateController.previewSample';
import startUpdate from '@salesforce/apex/BulkUpdateController.start';
import getJob from '@salesforce/apex/BulkUpdateController.getJob';
import getSavedLists from '@salesforce/apex/BulkUpdateController.getSavedLists';
import loadSavedList from '@salesforce/apex/BulkUpdateController.loadSavedList';
import saveSavedList from '@salesforce/apex/BulkUpdateController.saveSavedList';
import renameSavedList from '@salesforce/apex/BulkUpdateController.renameSavedList';
import deleteSavedList from '@salesforce/apex/BulkUpdateController.deleteSavedList';

jest.mock('@salesforce/apex/BulkUpdateController.getSavedLists', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.loadSavedList', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.saveSavedList', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.renameSavedList', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.deleteSavedList', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_SavedSaved',
  () => ({ default: 'Saved the list {0}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_SavedLoaded',
  () => ({ default: 'Loaded the list {0}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_SavedSkipped',
  () => ({ default: 'Loaded the list {0}. {1} change(s) were left out.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_SavedMissingFields',
  () => ({ default: 'The list {0} was not loaded: {1}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_SavedRenamed',
  () => ({ default: 'Renamed the list to {0}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_SavedDeleted',
  () => ({ default: 'Deleted the list {0}.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_SuperTransform_SavedOption', () => ({ default: '{0} ({1})' }), {
  virtual: true
});

jest.mock('@salesforce/apex/BulkUpdateController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getObjects', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getTargets', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getCopySources', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.countMatches', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.previewSample', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.start', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getJob', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_MatchCount',
  () => ({ default: '{0} {1} match.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_NoFilter',
  () => ({ default: 'No condition is set. This changes every {0}: {1} records.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_OverLimit',
  () => ({ default: '{0} records match, more than the {1} one run may change.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_AlreadyHeld',
  () => ({ default: '{0} of the {1} records shown already have these values.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_SuperTransform_ConfirmMessage',
  () => ({ default: 'Change {0} on {1} {2}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_BulkUpdate_Summary',
  () => ({ default: '{0} matched: {1} updated, {2} unchanged, {3} failed.' }),
  { virtual: true }
);

const OBJECTS = [
  { label: 'Account', value: 'Account' },
  { label: 'Contact', value: 'Contact' }
];
const TARGETS = [
  { apiName: 'Title', label: 'Title', dataType: 'string', nillable: true, picklistValues: [] },
  {
    apiName: 'Contact_Kind__c',
    label: 'Contact Kind',
    dataType: 'picklist',
    nillable: true,
    picklistValues: [{ label: 'Web', value: 'Web' }]
  }
];
const PREVIEW = {
  count: 3,
  objectLabel: 'Contacts',
  sample: [
    {
      recordId: '003A',
      name: 'Ana',
      changes: [{ label: 'Title', before: null, after: 'Coordinator', unchanged: false }]
    },
    {
      recordId: '003B',
      name: 'Ben',
      changes: [{ label: 'Title', before: 'Coordinator', after: 'Coordinator', unchanged: true }]
    },
    {
      recordId: '003C',
      name: 'Cy',
      changes: [{ label: 'Title', before: 'x', problem: 'Too long', unchanged: false }]
    }
  ]
};
const FINISHED = {
  recordId: 'a0B1',
  matched: 3,
  updated: 2,
  unchanged: 1,
  failed: 0,
  running: false,
  canUndo: true,
  failures: []
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
// The count waits for the conditions to rest (500 ms) before it asks.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const rest = () => new Promise((resolve) => setTimeout(resolve, 600));

function mount() {
  const element = createElement('c-super-transform', { is: SuperTransform });
  document.body.appendChild(element);
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const qa = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

async function chooseContact(element) {
  q(element, 'object').dispatchEvent(new CustomEvent('change', { detail: { value: 'Contact' } }));
  await flush();
  await rest();
  await flush();
}

async function setTitle(element, value) {
  q(element, 'field').dispatchEvent(new CustomEvent('change', { detail: { value: 'Title' } }));
  await flush();
  q(element, 'value').dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
}

describe('c-super-transform', () => {
  beforeEach(() => {
    getPage.mockResolvedValue({ allowed: true, maxChanges: 5, jobs: [] });
    getObjects.mockResolvedValue(OBJECTS);
    getTargets.mockResolvedValue(TARGETS);
    getCopySources.mockResolvedValue([]);
    countMatches.mockResolvedValue({
      count: 3,
      runLimit: 48000,
      overLimit: false,
      objectLabel: 'Contacts'
    });
    previewSample.mockResolvedValue(PREVIEW);
    startUpdate.mockResolvedValue(FINISHED);
    getJob.mockResolvedValue(FINISHED);
    getSavedLists.mockResolvedValue([]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says so, with no error, to a person without the permissions', async () => {
    getPage.mockResolvedValue({ allowed: false, jobs: [] });
    const element = mount();
    await flush();
    expect(q(element, 'no-permission')).not.toBeNull();
    expect(q(element, 'step-object')).toBeNull();
    expect(getObjects).not.toHaveBeenCalled();
  });

  it('filters the object list by the search box', async () => {
    const element = mount();
    await flush();
    q(element, 'object-search').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'cont' } })
    );
    await flush();
    expect(q(element, 'object').options.map((o) => o.value)).toEqual(['Contact']);
  });

  it('counts the records and warns when no condition is set', async () => {
    const element = mount();
    await flush();
    await chooseContact(element);
    expect(getTargets).toHaveBeenCalledWith({ objectName: 'Contact' });
    const sent = JSON.parse(countMatches.mock.calls[0][0].queryJson);
    expect(sent).toEqual({ version: 1, object: 'Contact', fields: ['Id'] });
    expect(q(element, 'count').textContent).toBe('3 Contacts match.');
    const warnings = qa(element, 'warning');
    expect(warnings).toHaveLength(1);
    expect(warnings[0].textContent).toContain('every Contact: 3 records');
  });

  it('counts again, once, after the conditions rest, and sends the filter', async () => {
    const element = mount();
    await flush();
    await chooseContact(element);
    countMatches.mockClear();
    const builder = element.shadowRoot.querySelector('c-filter-builder');
    const filter = JSON.stringify({ version: 1, conditions: [{ id: 1, field: 'Title' }] });
    builder.dispatchEvent(new CustomEvent('change', { detail: { value: filter, valid: true } }));
    builder.dispatchEvent(new CustomEvent('change', { detail: { value: filter, valid: true } }));
    await rest();
    await flush();
    expect(countMatches).toHaveBeenCalledTimes(1);
    expect(JSON.parse(countMatches.mock.calls[0][0].queryJson).filter.conditions).toHaveLength(1);
    expect(qa(element, 'warning')).toHaveLength(0);
  });

  it('warns over the run limit and keeps Preview disabled', async () => {
    countMatches.mockResolvedValue({
      count: 48001,
      runLimit: 48000,
      overLimit: true,
      objectLabel: 'Contacts'
    });
    const element = mount();
    await flush();
    await chooseContact(element);
    await setTitle(element, 'Coordinator');
    const texts = Array.from(qa(element, 'warning')).map((w) => w.textContent);
    expect(texts.some((text) => text.includes('more than the'))).toBe(true);
    expect(q(element, 'preview').disabled).toBe(true);
  });

  it('offers a picklist dropdown, and Fix Name Capitals as ready-made steps', async () => {
    const element = mount();
    await flush();
    await chooseContact(element);
    q(element, 'field').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Contact_Kind__c' } })
    );
    await flush();
    expect(q(element, 'picklist').options).toEqual([{ label: 'Web', value: 'Web' }]);

    q(element, 'field').dispatchEvent(new CustomEvent('change', { detail: { value: 'Title' } }));
    await flush();
    const actions = q(element, 'action').options.map((o) => o.value);
    expect(actions).toEqual(['set', 'clear', 'copy', 'transform', 'nameCase', 'phoneFormat']);
    q(element, 'action').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'nameCase' } })
    );
    await flush();
    const steps = element.shadowRoot.querySelector('c-import-column-transforms');
    expect(steps.transforms).toEqual([{ op: 'trim' }, { op: 'proper' }]);
  });

  it('offers Format Phone Number as one digit-format step (C-50f2)', async () => {
    const element = mount();
    await flush();
    await chooseContact(element);
    q(element, 'field').dispatchEvent(new CustomEvent('change', { detail: { value: 'Title' } }));
    await flush();
    q(element, 'action').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'phoneFormat' } })
    );
    await flush();
    const steps = element.shadowRoot.querySelector('c-import-column-transforms');
    expect(steps.transforms).toEqual([{ op: 'digits', pattern: '(###) ###-####', country: '1' }]);
    q(element, 'preview').click();
    await flush();
    expect(JSON.parse(previewSample.mock.calls[0][0].changesJson)).toEqual([
      {
        field: 'Title',
        action: 'transform',
        transforms: [{ op: 'digits', pattern: '(###) ###-####', country: '1' }]
      }
    ]);
  });

  it('offers no phone format on a picklist', async () => {
    const element = mount();
    await flush();
    await chooseContact(element);
    q(element, 'field').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Contact_Kind__c' } })
    );
    await flush();
    expect(q(element, 'action').options.map((o) => o.value)).not.toContain('phoneFormat');
  });

  describe('saved step lists (C-50f1)', () => {
    const ENTRY = {
      recordId: 'a0S1',
      name: 'Tidy titles',
      objectName: 'Contact',
      objectLabel: 'Contact'
    };
    const DEFINITION = {
      version: 1,
      object: 'Contact',
      filter: { version: 1, conditions: [{ id: 1, field: 'Title' }] },
      changes: [
        { field: 'Title', action: 'transform', transforms: [{ op: 'trim' }] },
        { field: 'Gone__c', action: 'set', value: 'x' }
      ]
    };

    it('lists the saved lists with their object', async () => {
      getSavedLists.mockResolvedValue([ENTRY]);
      const element = mount();
      await flush();
      expect(q(element, 'saved-pick').options).toEqual([
        { label: 'Tidy titles (Contact)', value: 'a0S1' }
      ]);
      expect(q(element, 'saved-load').disabled).toBe(true);
      expect(q(element, 'saved-delete').disabled).toBe(true);
    });

    it('says so when none are saved, and saves nothing without an object and a name', async () => {
      const element = mount();
      await flush();
      expect(q(element, 'saved-none')).not.toBeNull();
      expect(q(element, 'saved-save').disabled).toBe(true);
    });

    it('saves the page as a version 1 document and selects the new list', async () => {
      saveSavedList.mockResolvedValue({ ...ENTRY, definitionJson: '{}' });
      const element = mount();
      await flush();
      await chooseContact(element);
      await setTitle(element, 'Coordinator');
      q(element, 'saved-name').dispatchEvent(
        new CustomEvent('change', { detail: { value: 'Tidy titles' } })
      );
      await flush();
      getSavedLists.mockResolvedValue([ENTRY]);
      q(element, 'saved-save').click();
      await flush();
      await flush();
      const sent = saveSavedList.mock.calls[0][0];
      expect(sent.name).toBe('Tidy titles');
      expect(JSON.parse(sent.definitionJson)).toEqual({
        version: 1,
        object: 'Contact',
        changes: [{ field: 'Title', action: 'set', value: 'Coordinator' }]
      });
      expect(q(element, 'notice-message').textContent).toBe('Saved the list Tidy titles.');
      expect(q(element, 'saved-pick').value).toBe('a0S1');
    });

    it('loads a list, leaving out a change whose field is gone, and counts again', async () => {
      getSavedLists.mockResolvedValue([ENTRY]);
      loadSavedList.mockResolvedValue({
        ...ENTRY,
        missingFields: [],
        definitionJson: JSON.stringify(DEFINITION)
      });
      const element = mount();
      await flush();
      q(element, 'saved-pick').dispatchEvent(
        new CustomEvent('change', { detail: { value: 'a0S1' } })
      );
      await flush();
      q(element, 'saved-load').click();
      await flush();
      await rest();
      await flush();
      expect(loadSavedList).toHaveBeenCalledWith({ recordId: 'a0S1' });
      expect(getTargets).toHaveBeenCalledWith({ objectName: 'Contact' });
      expect(q(element, 'object').value).toBe('Contact');
      expect(JSON.parse(countMatches.mock.calls[0][0].queryJson).filter.conditions).toHaveLength(1);
      const steps = element.shadowRoot.querySelector('c-import-column-transforms');
      expect(steps.transforms).toEqual([{ op: 'trim' }]);
      expect(q(element, 'notice-message').textContent).toBe(
        'Loaded the list Tidy titles. 1 change(s) were left out.'
      );
      expect(q(element, 'preview').disabled).toBe(false);
    });

    it('does not load a list whose filter uses a missing field, and names the fields', async () => {
      getSavedLists.mockResolvedValue([ENTRY]);
      loadSavedList.mockResolvedValue({
        ...ENTRY,
        missingFields: ['Gone__c', 'Account.Nothing__c'],
        definitionJson: JSON.stringify(DEFINITION)
      });
      const element = mount();
      await flush();
      q(element, 'saved-pick').dispatchEvent(
        new CustomEvent('change', { detail: { value: 'a0S1' } })
      );
      await flush();
      q(element, 'saved-load').click();
      await flush();
      expect(q(element, 'error-message').textContent).toContain('Gone__c, Account.Nothing__c');
      expect(q(element, 'error-message').textContent).toContain('Tidy titles');
      expect(getTargets).not.toHaveBeenCalled();
      expect(q(element, 'step-changes')).not.toBeNull();
      expect(q(element, 'object').value).toBeUndefined();
      expect(q(element, 'notice-message')).toBeNull();
    });

    it('renames the selected list', async () => {
      getSavedLists.mockResolvedValue([ENTRY]);
      renameSavedList.mockResolvedValue({ ...ENTRY, name: 'Titles' });
      const element = mount();
      await flush();
      q(element, 'saved-pick').dispatchEvent(
        new CustomEvent('change', { detail: { value: 'a0S1' } })
      );
      await flush();
      q(element, 'saved-name').dispatchEvent(
        new CustomEvent('change', { detail: { value: 'Titles' } })
      );
      await flush();
      q(element, 'saved-rename').click();
      await flush();
      expect(renameSavedList).toHaveBeenCalledWith({ recordId: 'a0S1', name: 'Titles' });
      expect(q(element, 'notice-message').textContent).toBe('Renamed the list to Titles.');
    });

    it('deletes only after the confirmation', async () => {
      getSavedLists.mockResolvedValue([ENTRY]);
      const element = mount();
      await flush();
      q(element, 'saved-pick').dispatchEvent(
        new CustomEvent('change', { detail: { value: 'a0S1' } })
      );
      await flush();
      BarnConfirmModal.open = jest.fn().mockResolvedValue(false);
      q(element, 'saved-delete').click();
      await flush();
      expect(deleteSavedList).not.toHaveBeenCalled();
      BarnConfirmModal.open = jest.fn().mockResolvedValue(true);
      getSavedLists.mockResolvedValue([]);
      q(element, 'saved-delete').click();
      await flush();
      await flush();
      expect(deleteSavedList).toHaveBeenCalledWith({ recordId: 'a0S1' });
      expect(q(element, 'notice-message').textContent).toBe('Deleted the list Tidy titles.');
      expect(q(element, 'saved-none')).not.toBeNull();
    });
  });

  it('previews old and new values, highlights changes and counts those already held', async () => {
    const element = mount();
    await flush();
    await chooseContact(element);
    await setTitle(element, 'Coordinator');
    q(element, 'preview').click();
    await flush();
    expect(JSON.parse(previewSample.mock.calls[0][0].changesJson)).toEqual([
      { field: 'Title', action: 'set', value: 'Coordinator' }
    ]);
    const cells = qa(element, 'cell');
    expect(cells).toHaveLength(3);
    expect(cells[0].className).toContain('changed');
    expect(cells[1].className).not.toContain('changed');
    expect(cells[2].className).toContain('slds-text-color_error');
    expect(cells[2].textContent).toContain('Too long');
    expect(q(element, 'already-held').textContent).toBe(
      '1 of the 3 records shown already have these values.'
    );
  });

  it('clears the preview when a change is edited', async () => {
    const element = mount();
    await flush();
    await chooseContact(element);
    await setTitle(element, 'Coordinator');
    q(element, 'preview').click();
    await flush();
    expect(q(element, 'preview-table')).not.toBeNull();
    q(element, 'value').dispatchEvent(new CustomEvent('change', { detail: { value: 'Manager' } }));
    await flush();
    expect(q(element, 'preview-table')).toBeNull();
    expect(q(element, 'run').disabled).toBe(true);
  });

  it('runs only after the confirmation, then shows the result and the undo hint', async () => {
    const element = mount();
    await flush();
    await chooseContact(element);
    await setTitle(element, 'Coordinator');
    q(element, 'preview').click();
    await flush();

    BarnConfirmModal.open.mockResolvedValue(false);
    q(element, 'run').click();
    await flush();
    expect(startUpdate).not.toHaveBeenCalled();

    BarnConfirmModal.open.mockResolvedValue(true);
    q(element, 'run').click();
    await flush();
    await flush();
    const dialog = BarnConfirmModal.open.mock.calls[1][0];
    expect(dialog.message).toBe('Change Title on 3 Contacts.');
    expect(dialog.typeToConfirm).toBeUndefined();
    expect(startUpdate).toHaveBeenCalledWith(expect.objectContaining({ confirmedCount: 3 }));
    expect(q(element, 'summary').textContent).toBe('3 matched: 2 updated, 1 unchanged, 0 failed.');
    expect(q(element, 'undo-hint')).not.toBeNull();
  });

  it('asks for the number to be typed over 200 records', async () => {
    previewSample.mockResolvedValue({ ...PREVIEW, count: 1250 });
    BarnConfirmModal.open.mockResolvedValue(false);
    const element = mount();
    await flush();
    await chooseContact(element);
    await setTitle(element, 'Coordinator');
    q(element, 'preview').click();
    await flush();
    q(element, 'run').click();
    await flush();
    expect(BarnConfirmModal.open.mock.calls[0][0].typeToConfirm).toBe('1250');
  });

  it('shows a refusal in plain words', async () => {
    previewSample.mockRejectedValue({ body: { message: 'No contacts match.' } });
    const element = mount();
    await flush();
    await chooseContact(element);
    await setTitle(element, 'Coordinator');
    q(element, 'preview').click();
    await flush();
    expect(q(element, 'error-message').textContent).toBe('No contacts match.');
  });
});
