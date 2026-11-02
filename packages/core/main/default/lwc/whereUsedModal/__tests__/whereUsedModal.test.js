import { createElement } from 'lwc';
import WhereUsedModal from 'c/whereUsedModal';
import findReferences from '@salesforce/apex/WhereUsedController.findReferences';
import { groupReferences, retireSteps, doneCount } from '../whereUsedModel';

jest.mock('@salesforce/apex/WhereUsedController.findReferences', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Core_SetupAssistant_ProgressFormat',
  () => ({ default: '{0} of {1} steps done' }),
  {
    virtual: true
  }
);

const flush = async (turns = 10) => {
  if (turns > 0) {
    await Promise.resolve();
    await flush(turns - 1);
  }
};

const RESULT = {
  objectName: 'Contact',
  objectLabel: 'Contact',
  fieldName: 'Department',
  fieldLabel: 'Department',
  deletable: false,
  incomplete: false,
  findUrl: '/lightning/n/Find?c__object=Contact',
  references: [
    {
      kind: 'importMapping',
      kindLabel: 'Import Mappings',
      name: 'People',
      recordId: 'a01000000000001',
      parts: ['Column "Job"'],
      breaks: 'Imports fail.',
      editUrl: '/lightning/n/Data_Manager'
    },
    {
      kind: 'savedQuery',
      kindLabel: 'Saved Find Queries',
      name: 'A private saved query owned by Sam',
      recordId: null,
      parts: ['Filter', 'Sort'],
      breaks: 'Find refuses.',
      editUrl: null
    },
    {
      kind: 'savedQuery',
      kindLabel: 'Saved Find Queries',
      name: 'Board list',
      recordId: 'a02000000000001',
      parts: ['Columns'],
      breaks: 'Find refuses.',
      editUrl: '/lightning/n/Find?c__savedQueryId=a02000000000001'
    }
  ]
};

async function render(props) {
  const element = createElement('c-where-used-modal', { is: WhereUsedModal });
  Object.assign(element, props);
  const closed = jest.fn();
  element.addEventListener('close', () => closed());
  document.body.appendChild(element);
  await flush();
  return { element, closed };
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('whereUsedModel', () => {
  it('groups references by kind in the order given, joining their parts', () => {
    const groups = groupReferences(RESULT.references);
    expect(groups.map((group) => group.label)).toEqual(['Import Mappings', 'Saved Find Queries']);
    expect(groups[1].items.map((item) => item.parts)).toEqual(['Filter, Sort', 'Columns']);
    expect(groups[1].items[0].url).toBeNull();
    expect(groupReferences(undefined)).toEqual([]);
  });

  it('offers deleting only a field the org can delete, and counts ticks', () => {
    expect(retireSteps({ references: [], deletable: true }).map((step) => step.key)).toEqual([
      'noReferences',
      'salesforce',
      'backup',
      'hide',
      'delete'
    ]);
    const steps = retireSteps(RESULT);
    expect(steps[0].key).toBe('references');
    expect(steps[4]).toEqual({ key: 'cannotDelete', link: null });
    expect(doneCount(steps, new Set(['hide', 'backup', 'other']))).toBe(2);
    expect(doneCount(steps)).toBe(0);
  });
});

describe('c-where-used-modal', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists each use with a link to edit it, and the Retire a Field steps', async () => {
    findReferences.mockResolvedValue(RESULT);
    const { element, closed } = await render({
      objectName: 'Contact',
      objectLabel: 'Contact',
      fieldName: 'Department',
      fieldLabel: 'Department'
    });

    expect(findReferences).toHaveBeenCalledWith({ objectName: 'Contact', fieldName: 'Department' });
    expect(all(element, '[data-id="reference"]')).toHaveLength(3);
    expect(all(element, '[data-id="edit-link"]').map((link) => link.getAttribute('href'))).toEqual([
      '/lightning/n/Data_Manager',
      '/lightning/n/Find?c__savedQueryId=a02000000000001'
    ]);
    expect(one(element, '[data-id="setup-link"]').getAttribute('href')).toBe(
      '/lightning/setup/ObjectManager/Contact/FieldsAndRelationships/Department/view'
    );
    expect(all(element, 'li[data-step]').map((step) => step.dataset.step)).toEqual([
      'references',
      'salesforce',
      'backup',
      'hide',
      'cannotDelete'
    ]);
    expect(
      all(element, '[data-id="step-link"]').map((link) => link.getAttribute('href'))
    ).toContain('/lightning/n/Find?c__object=Contact');

    const hide = one(element, 'lightning-input[data-step="hide"]');
    hide.checked = true;
    hide.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(one(element, '[data-id="progress"]').textContent).toContain('1 of 5 steps done');

    one(element, '[data-id="close"]').click();
    expect(closed).toHaveBeenCalled();
  });

  it('switches to the whole object, where there is no checklist, and says when nothing uses it', async () => {
    findReferences.mockResolvedValue(RESULT);
    const { element } = await render({ objectName: 'Contact', fieldName: 'Department' });
    findReferences.mockResolvedValue({
      ...RESULT,
      fieldName: null,
      references: [],
      incomplete: true
    });

    one(element, '[data-id="switch"]').click();
    await flush();

    expect(findReferences).toHaveBeenLastCalledWith({ objectName: 'Contact', fieldName: null });
    expect(one(element, '[data-id="none"]')).not.toBeNull();
    expect(one(element, '[data-id="incomplete"]')).not.toBeNull();
    expect(one(element, '[data-id="retire"]')).toBeNull();
    expect(one(element, '[data-id="setup-link"]').getAttribute('href')).toBe(
      '/lightning/setup/ObjectManager/Contact/view'
    );
  });

  it('shows a refusal as it comes', async () => {
    findReferences.mockRejectedValue({ body: { message: 'You need the permission.' } });
    const { element } = await render({ objectName: 'Contact', fieldName: 'Email' });

    expect(one(element, '[data-id="error"]').textContent).toContain('You need the permission.');
    expect(one(element, '[data-id="retire"]')).toBeNull();
  });
});
