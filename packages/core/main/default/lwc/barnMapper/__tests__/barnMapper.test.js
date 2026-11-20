import { createElement } from 'lwc';
import BarnMapper from 'c/barnMapper';
import getObjects from '@salesforce/apex/MapController.getObjects';
import getTargetFields from '@salesforce/apex/MapController.getTargetFields';
import previewMap from '@salesforce/apex/MapController.previewMap';
import listObjects from '@salesforce/apex/FindController.listObjects';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/MapController.getObjects', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MapController.getTargetFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MapController.previewMap', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.listObjects', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/QueryFieldCatalog.getObjectInfo', () => ({ default: jest.fn() }), {
  virtual: true
});

const FIELDS = [
  { apiName: 'Email', label: 'Email', dataType: 'email', length: 80 },
  { apiName: 'LastName', label: 'Last Name', dataType: 'string', length: 80, required: true },
  { apiName: 'Birthdate', label: 'Birthdate', dataType: 'date' },
  { apiName: 'AccountId', label: 'Account ID', dataType: 'reference', referenceTo: 'Account' }
];

const SAMPLE = { profile: { email: ' Pat@Example.org ', last_name: 'Lee', born: 'soon' } };

const MAP = {
  version: 4,
  from: { kind: 'json', sample: SAMPLE },
  to: { kind: 'record', object: 'Contact' }
};

function createComponent(value = MAP) {
  const element = createElement('c-barn-mapper', { is: BarnMapper });
  element.value = value;
  document.body.appendChild(element);
  return element;
}

/** Lets the Apex promises settle and the preview timer (300 ms) run. */
function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 350)).then(() => Promise.resolve());
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function findAll(element, id) {
  return Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));
}

function targetRow(element, target) {
  return element.shadowRoot.querySelector(`[data-id="target"][data-target="${target}"]`);
}

describe('c-barn-mapper', () => {
  beforeEach(() => {
    getObjects.mockResolvedValue([{ label: 'Contact', value: 'Contact' }]);
    listObjects.mockResolvedValue([{ label: 'Contact', value: 'Contact' }]);
    getTargetFields.mockResolvedValue(FIELDS);
    getObjectInfo.mockResolvedValue({ fields: [] });
    previewMap.mockResolvedValue({
      samples: [
        {
          values: [
            { target: 'Record.Email', value: 'pat@example.org' },
            { target: 'Record.LastName', value: 'Lee' }
          ]
        }
      ]
    });
    setHelpTextForTest({
      Core_Mapper_SentenceGets: '{0} gets {1}',
      Core_Mapper_SentenceThen: ', then {0}'
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    clearHelpTextForTest();
    jest.clearAllMocks();
  });

  it('lists the sample, matches exact names and marks guesses to check', async () => {
    const element = createComponent({
      ...MAP,
      from: {
        kind: 'json',
        sample: { profile: { email: 'pat@example.org', family_last_name: 'Lee' } }
      }
    });
    const changes = [];
    element.addEventListener('change', (event) => changes.push(event.detail));
    await settle();

    expect(getTargetFields).toHaveBeenCalledWith({ objectName: 'Contact' });
    const sources = findAll(element, 'source').map((item) => item.dataset.dragId);
    expect(sources).toEqual(['profile.email', 'profile.family_last_name']);

    const document = JSON.parse(element.value);
    const email = document.columns.find((column) => column.target === 'Record.Email');
    expect(email.source).toBe('profile.email');
    // Last Name is a best guess (family_last_name), so Save waits until it is accepted.
    const lastName = document.columns.find((column) => column.target === 'Record.LastName');
    expect(lastName.source).toBe('profile.family_last_name');
    expect(changes[changes.length - 1].pendingGuesses).toBeGreaterThan(0);
    expect(targetRow(element, 'Record.LastName').querySelector('[data-id="guess"]')).not.toBeNull();
    expect(find(element, 'guess-pending')).not.toBeNull();

    find(element, 'accept-all').click();
    await settle();
    expect(changes[changes.length - 1].pendingGuesses).toBe(0);
    expect(find(element, 'guess-pending')).toBeNull();
    await expectAccessible(element);
  });

  it('reads each filled field as one sentence and previews the sample', async () => {
    const element = createComponent({
      ...MAP,
      columns: [
        {
          source: 'profile.email',
          target: 'Record.Email',
          transforms: [{ op: 'trim' }, { op: 'lower' }]
        }
      ]
    });
    await settle();

    expect(
      targetRow(element, 'Record.Email').querySelector('[data-id="sentence"]').textContent
    ).toBe(
      'Email gets profile, email, then c.Core_Import_ChangesOpTrim, then c.Core_Import_ChangesOpLower.'
    );
    expect(previewMap).toHaveBeenCalled();
    const request = previewMap.mock.calls[0][0];
    expect(JSON.parse(request.samplesJson)[0]['profile.email']).toBe(' Pat@Example.org ');
    const rows = findAll(element, 'preview-row');
    expect(rows.length).toBeGreaterThan(0);
    expect(rows[0].textContent).toContain('pat@example.org');
  });

  it('flags a value the field would refuse', async () => {
    previewMap.mockResolvedValue({
      samples: [{ values: [{ target: 'Record.Birthdate', value: 'soon' }] }]
    });
    const element = createComponent({
      ...MAP,
      columns: [{ source: 'profile.born', target: 'Record.Birthdate' }]
    });
    await settle();

    const labels = findAll(element, 'flag').map((badge) => badge.label);
    expect(labels).toContain('c.Core_Mapper_FlagNotDate');
    // Last Name is required and not filled.
    expect(labels).toContain('c.Core_Mapper_FlagRequired');
  });

  it('picks a source from a list, without dragging', async () => {
    const element = createComponent({ ...MAP, columns: [] });
    await settle();
    const before = JSON.parse(element.value).columns.length;

    targetRow(element, 'Record.Birthdate').querySelector('[data-id="pick"]').click();
    await settle();
    const picker = targetRow(element, 'Record.Birthdate').querySelector('[data-id="picker"]');
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'profile.born' } }));
    await settle();

    const columns = JSON.parse(element.value).columns;
    expect(columns.length).toBe(before + 1);
    expect(columns.find((column) => column.target === 'Record.Birthdate').source).toBe(
      'profile.born'
    );
    expect(find(element, 'announcement').textContent).toBe('c.Core_Mapper_Mapped');
  });

  it('keeps fixed values, defaults and a lookup in the map', async () => {
    const element = createComponent({
      ...MAP,
      columns: [{ source: 'profile.last_name', target: 'Record.AccountId' }]
    });
    await settle();

    targetRow(element, 'Record.AccountId').querySelector('[data-id="details"]').click();
    await settle();
    const row = targetRow(element, 'Record.AccountId');
    row
      .querySelector('[data-id="lookup-field"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Name' } }));
    await settle();
    targetRow(element, 'Record.AccountId')
      .querySelector('[data-id="lookup-not-found"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'leaveEmpty' } }));
    targetRow(element, 'Record.AccountId')
      .querySelector('[data-id="default"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Household' } }));
    await settle();

    const saved = JSON.parse(element.value);
    const account = saved.columns.find((column) => column.target === 'Record.AccountId');
    expect(account.lookup).toEqual({ object: 'Account', field: 'Name', notFound: 'leaveEmpty' });
    expect(saved.defaults).toEqual([{ target: 'Record.AccountId', value: 'Household' }]);
    expect(find(element, 'lookup-sentence').textContent).toBe('c.Core_Mapper_LookupSentence');

    targetRow(element, 'Record.Email').querySelector('[data-id="details"]').click();
    await settle();
    targetRow(element, 'Record.Email')
      .querySelector('[data-id="fixed"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'none@example.org' } }));
    await settle();
    const fixed = JSON.parse(element.value).columns.find(
      (column) => column.target === 'Record.Email'
    );
    expect(fixed.value).toBe('none@example.org');
    expect(fixed.source).toBeUndefined();
  });

  it('sets matching in one sentence with what it risks', async () => {
    const element = createComponent();
    await settle();

    find(element, 'match-by').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'field' } })
    );
    await settle();
    // A field to match by is needed before the map is complete.
    expect(find(element, 'problems')).not.toBeNull();
    find(element, 'match-field').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Email' } })
    );
    await settle();

    expect(JSON.parse(element.value).match).toMatchObject({ by: 'field', field: 'Email' });
    expect(find(element, 'problems')).toBeNull();
    expect(find(element, 'match-sentence').textContent).toBe('c.Core_Mapper_MatchSentence');
    expect(find(element, 'match-risk').textContent).toBe('c.Core_Mapper_MatchRiskField');
  });

  it('checks the map over the samples before running', async () => {
    const element = createComponent({
      ...MAP,
      columns: [{ source: 'profile.born', target: 'Record.Birthdate' }]
    });
    await settle();
    previewMap.mockResolvedValue({
      samples: [
        { values: [{ target: 'Record.Birthdate', value: 'soon' }] },
        { values: [{ target: 'Record.Birthdate', value: '2020-01-02' }] }
      ]
    });

    find(element, 'check').click();
    await settle();

    const results = find(element, 'check-results');
    expect(results).not.toBeNull();
    expect(results.querySelectorAll('li').length).toBeGreaterThan(0);
    expect(results.querySelector('p').textContent).toBe('c.Core_Mapper_CheckFound');
  });

  it('refuses JSON it cannot read and keeps the sample it can', async () => {
    const element = createComponent({ version: 4, from: { kind: 'json' }, to: { kind: 'json' } });
    await settle();

    const box = find(element, 'json');
    box.dispatchEvent(new CustomEvent('change', { detail: { value: '{ not json' } }));
    find(element, 'use-json').click();
    await settle();
    expect(find(element, 'sample-error').message).toBe('c.Core_Mapper_JsonUnreadable');

    box.dispatchEvent(
      new CustomEvent('change', { detail: { value: '[{"a":{"b":1}},{"a":{"b":2}}]' } })
    );
    find(element, 'use-json').click();
    await settle();
    expect(find(element, 'sample-error')).toBeNull();
    expect(findAll(element, 'source').map((item) => item.dataset.dragId)).toContain('a.b');
    expect(JSON.parse(element.value).from.sample).toEqual({ a: { b: 1 } });
  });

  it('adds a JSON body key only when it is a path', async () => {
    const element = createComponent({
      version: 4,
      from: { kind: 'columns' },
      to: { kind: 'json' }
    });
    await settle();

    const key = find(element, 'new-key');
    key.dispatchEvent(new CustomEvent('change', { detail: { value: 'bad key!' } }));
    find(element, 'add-key').click();
    await settle();
    expect(find(element, 'key-error').textContent).toBe('c.Core_Mapper_KeyNotPath');

    key.dispatchEvent(new CustomEvent('change', { detail: { value: 'contact.emails[0]' } }));
    find(element, 'add-key').click();
    await settle();
    expect(find(element, 'key-error')).toBeNull();
    expect(targetRow(element, 'contact.emails[0]')).not.toBeNull();
    await expectAccessible(element);
  });

  it('keeps the parts of a map it does not know and skips a broken line, saying so', async () => {
    const element = createComponent({
      ...MAP,
      columns: [{ source: 'profile.email' }],
      futurePart: { kept: true }
    });
    await settle();

    expect(find(element, 'skipped').message).toBe('c.Core_Mapper_Skipped');
    expect(JSON.parse(element.value).futurePart).toEqual({ kept: true });
  });

  it('shows the server message when the fields cannot be read', async () => {
    getTargetFields.mockRejectedValue({ body: { message: 'You cannot edit Contacts.' } });
    const element = createComponent();
    await settle();

    expect(find(element, 'load-error').message).toBe('You cannot edit Contacts.');
    expect(find(element, 'no-targets')).not.toBeNull();
  });

  describe("drawing Super Importer's Check Columns step (MAP-05)", () => {
    const SETUP = {
      objectName: 'Contact',
      headers: ['E-mail', 'Surname', 'Org'],
      rows: [{ 'E-mail': 'pat@example.org', Surname: 'Lee', Org: 'Riverbend' }],
      targets: [
        { value: 'Record.Email', label: 'Email' },
        { value: 'Record.LastName', label: 'Last Name' },
        { value: 'Record.AccountId', label: 'Account ID' },
        { value: 'Record.Grade__c', label: 'Grade' }
      ],
      lookupChoices: {
        'Record.AccountId': [
          { label: 'Salesforce record ID', value: 'Id' },
          { label: 'Account Name', value: 'Name' }
        ]
      },
      canCreateFields: true
    };

    function createImporting(columns) {
      const element = createElement('c-barn-mapper', { is: BarnMapper });
      element.importSetup = SETUP;
      element.value = {
        version: 4,
        from: { kind: 'columns' },
        to: { kind: 'record', object: 'Contact' },
        columns
      };
      document.body.appendChild(element);
      return element;
    }

    it('fixes the file and the fields, and leaves matching and fixed values to the template', async () => {
      const element = createImporting([
        { source: 'E-mail', target: 'Record.Email' },
        { source: 'Surname', target: 'Record.LastName', guessed: true }
      ]);
      await settle();

      expect(getObjects).not.toHaveBeenCalled();
      expect(find(element, 'setup')).toBeNull();
      expect(find(element, 'match-card')).toBeNull();
      expect(findAll(element, 'source').map((item) => item.dataset.dragId)).toEqual([
        'E-mail',
        'Surname',
        'Org'
      ]);
      // Only the template's fields, in its order; one created a moment ago reads as text.
      const targets = findAll(element, 'target').map((row) => row.dataset.target);
      expect(targets).toEqual(expect.arrayContaining(SETUP.targets.map((t) => t.value)));
      expect(targets).not.toContain('Record.Birthdate');
      // Nothing is matched again on open, and the template's best guess still waits.
      expect(JSON.parse(element.value).columns).toHaveLength(2);
      expect(
        targetRow(element, 'Record.LastName').querySelector('[data-id="guess"]')
      ).not.toBeNull();
      // Create Field only on a column not yet loaded.
      expect(findAll(element, 'create-field').map((button) => button.dataset.source)).toEqual([
        'Org'
      ]);
      await expectAccessible(element);
    });

    it('moves a column to one field, keeps its lookup field and empty-cell choice, and asks for a new field', async () => {
      const element = createImporting([
        { source: 'E-mail', target: 'Record.Email' },
        { source: 'Org', target: 'Record.AccountId' }
      ]);
      const changes = [];
      element.addEventListener('change', (event) => changes.push(event.detail));
      const created = [];
      element.addEventListener('createfield', (event) => created.push(event.detail.source));
      await settle();

      targetRow(element, 'Record.Grade__c').querySelector('[data-id="pick"]').click();
      await settle();
      targetRow(element, 'Record.Grade__c')
        .querySelector('[data-id="picker"]')
        .dispatchEvent(new CustomEvent('change', { detail: { value: 'E-mail' } }));
      await settle();
      let columns = changes[changes.length - 1].columns;
      expect(columns.filter((column) => column.source === 'E-mail')).toEqual([
        { source: 'E-mail', target: 'Record.Grade__c' }
      ]);

      targetRow(element, 'Record.AccountId').querySelector('[data-id="details"]').click();
      await settle();
      const row = targetRow(element, 'Record.AccountId');
      expect(row.querySelector('[data-id="lookup-not-found"]')).toBeNull();
      expect(row.querySelector('[data-id="fixed"]')).toBeNull();
      expect(row.querySelector('[data-id="lookup-field"]').options.map((o) => o.value)).toEqual([
        'Id',
        'Name'
      ]);
      row
        .querySelector('[data-id="lookup-field"]')
        .dispatchEvent(new CustomEvent('change', { detail: { value: 'Name' } }));
      await settle();
      targetRow(element, 'Record.AccountId')
        .querySelector('[data-id="blank-clears"]')
        .dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));
      await settle();
      columns = changes[changes.length - 1].columns;
      expect(columns.find((column) => column.source === 'Org')).toEqual({
        source: 'Org',
        target: 'Record.AccountId',
        lookupField: 'Name',
        blankClears: true
      });

      find(element, 'create-field').click();
      expect(created).toEqual(['Surname']);
    });
  });
});
