import fs from 'fs';
import path from 'path';
import {
  applyToColumns,
  autoMatch,
  checkValue,
  columnSentence,
  fromImportMapping,
  isPath,
  keptSample,
  normalize,
  parseMap,
  pathLabel,
  pathsFromSample,
  previewRows,
  problems,
  readPath,
  sampleValues,
  samplesFromJson,
  serialize,
  sourcesFromJson,
  sourcesFromRecord,
  sourcesFromRows,
  summarize,
  fromImportColumns,
  toImportColumns,
  toChanges,
  MAX_COLUMNS,
  VERSION
} from 'c/mapDocument';
import { score } from '../../importFieldPicker/fieldSuggest';

// The fixture the Apex tests read too (MapControllerTest).
// eslint-disable-next-line no-undef
const HERE = __dirname;
const FIXTURE = JSON.parse(
  fs.readFileSync(path.join(HERE, '../../../staticresources/MapDocumentFixture.json'), 'utf8')
);

describe('c-map-document against the shared fixture', () => {
  FIXTURE.paths.valid.forEach((each) => {
    it(`accepts the path "${each}"`, () => {
      expect(isPath(each)).toBe(true);
    });
  });
  FIXTURE.paths.invalid.forEach((each) => {
    it(`refuses the path "${each}"`, () => {
      expect(isPath(each)).toBe(false);
    });
  });
  FIXTURE.valid.forEach((each) => {
    it(`saves ${each.name}`, () => {
      expect(problems(each.document)).toEqual([]);
    });
  });
  FIXTURE.invalid
    .filter((each) => !each.serverOnly)
    .forEach((each) => {
      it(`refuses ${each.name}`, () => {
        expect(problems(each.document).length).toBeGreaterThan(0);
      });
    });
});

describe('paths and samples', () => {
  const sample = {
    profile: { email: 'a@b.org', last_name: 'smith', 'bad key': 'x' },
    order: { lines: [{ sku: 'A1', qty: 2 }, { sku: 'B2' }] },
    tags: [],
    active: true
  };

  it('reads a path, blank when it finds nothing', () => {
    expect(readPath(sample, 'profile.email')).toBe('a@b.org');
    expect(readPath(sample, 'order.lines[1].sku')).toBe('B2');
    expect(readPath(sample, 'order.lines[5].sku')).toBe('');
    expect(readPath(sample, 'active')).toBe('true');
    expect(readPath(sample, 'nothing.here')).toBe('');
    expect(readPath(sample, 'not a path')).toBe('');
  });

  it('labels a path in plain words', () => {
    expect(pathLabel('profile.email')).toBe('profile, email');
    expect(pathLabel('order.lines[0].sku')).toBe('order, lines 1, sku');
  });

  it('lists every value of a sample through the first item of a list', () => {
    expect(pathsFromSample(sample)).toEqual([
      'profile.email',
      'profile.last_name',
      'order.lines[0].sku',
      'order.lines[0].qty',
      'tags',
      'active'
    ]);
    expect(pathsFromSample([{ id: 1 }, { id: 2 }])).toEqual(['id']);
  });

  it('reads pasted JSON as samples', () => {
    expect(samplesFromJson('[{"a":1},{"a":2},3]').samples).toHaveLength(2);
    expect(samplesFromJson('{"a":1}').samples).toEqual([{ a: 1 }]);
    expect(samplesFromJson('{oops').error).toBe('unreadable');
    expect(samplesFromJson('[1,2]').error).toBe('unreadable');
    expect(samplesFromJson('').samples).toEqual([]);
  });

  it('keeps a sample only when it fits', () => {
    expect(keptSample([{ a: 1 }])).toEqual({ a: 1 });
    expect(keptSample([{ a: 'x'.repeat(20001) }])).toBeUndefined();
    expect(keptSample([])).toBeUndefined();
  });

  it('builds sources with examples from rows, payloads and a record', () => {
    const rows = [{ Email: 'a@b.org' }, { Email: '' }, { Email: 'c@d.org' }];
    expect(sourcesFromRows(['Email'], rows)).toEqual([
      { name: 'Email', label: 'Email', examples: ['a@b.org', 'c@d.org'] }
    ]);
    const fromJson = sourcesFromJson([sample]);
    expect(fromJson[0]).toEqual({
      name: 'profile.email',
      label: 'profile, email',
      examples: ['a@b.org']
    });
    expect(sourcesFromRecord([{ apiName: 'Email', label: 'Email' }], { Email: 'e@f.org' })).toEqual(
      [{ name: 'Email', label: 'Email', examples: ['e@f.org'] }]
    );
  });

  it('reads a sample as the preview call takes it', () => {
    expect(sampleValues('columns', { Email: 'a@b.org' }, ['Email', 'Phone'])).toEqual({
      Email: 'a@b.org',
      Phone: ''
    });
    expect(sampleValues('json', sample, ['profile.email'])).toEqual({
      'profile.email': 'a@b.org'
    });
    expect(sampleValues('record', { Account: { Name: 'Acme' } }, ['Account.Name'])).toEqual({
      'Account.Name': 'Acme'
    });
  });
});

describe('auto-match', () => {
  const targets = [
    { value: 'Record.Email', label: 'Email', name: 'Email' },
    { value: 'Record.LastName', label: 'Last Name', name: 'LastName' },
    { value: 'Record.FirstName', label: 'First Name', name: 'FirstName' },
    { value: 'Record.Volunteer_Status__c', label: 'Volunteer Status', name: 'Volunteer_Status__c' },
    { value: 'Record.MailingCity', label: 'Mailing City', name: 'MailingCity' }
  ];

  it('normalizes names', () => {
    // A prefixed name, built here so the namespace check does not read it as a reference.
    expect(normalize(['barn', 'Volunteer_Status__c'].join('__'))).toBe('volunteerstatus');
    expect(normalize('E-mail')).toBe('email');
    expect(normalize('First Name')).toBe('firstname');
  });

  it('matches exact names first, then best guesses marked to check', () => {
    const sources = [
      { name: 'profile.email', label: 'profile, email' },
      { name: 'Last Name', label: 'Last Name' },
      { name: 'volunteer_status', label: 'volunteer_status' },
      { name: 'City', label: 'City' },
      { name: 'Shoe Size', label: 'Shoe Size' }
    ];
    const columns = autoMatch(sources, targets, [], score);
    expect(columns).toEqual([
      { source: 'profile.email', target: 'Record.Email' },
      { source: 'Last Name', target: 'Record.LastName' },
      { source: 'volunteer_status', target: 'Record.Volunteer_Status__c' },
      { source: 'City', target: 'Record.MailingCity', guessed: true }
    ]);
  });

  it('keeps the columns already set and never fills a target twice', () => {
    const kept = [{ source: 'Mail', target: 'Record.Email' }];
    const columns = autoMatch([{ name: 'Email', label: 'Email' }], targets, kept, score);
    expect(columns).toEqual(kept);
  });

  it('makes no guesses without a scorer', () => {
    expect(autoMatch([{ name: 'City', label: 'City' }], targets, [])).toEqual([]);
  });
});

describe('reading, checking and writing a document', () => {
  it('reads every template mapping as a version 4 map from columns to a record', () => {
    FIXTURE.valid.forEach((each) => {
      const { document, skipped } = parseMap(JSON.stringify(each.document));
      expect(document.version).toBe(VERSION);
      expect(skipped).toBe(0);
      expect(document.columns).toHaveLength(each.document.columns.length);
    });
    const { document } = parseMap(FIXTURE.valid[0].document);
    expect(document.from).toEqual({ kind: 'columns' });
    expect(document.to).toEqual({ kind: 'record' });
  });

  it('keeps keys it does not know, such as a template row rule', () => {
    const { document } = parseMap(FIXTURE.valid[1].document);
    expect(document.skipRows).toEqual(FIXTURE.valid[1].document.skipRows);
    expect(document.columns[1].lookupField).toBe('Name');
  });

  it('skips broken columns and second columns for a target, and counts them', () => {
    const { document, skipped } = parseMap({
      version: 4,
      columns: [
        { source: 'a', target: 'Record.Email' },
        { source: 'b', target: 'record.email' },
        { target: 'Record.Phone' },
        'nonsense',
        { source: 'c', target: 'Record.Title', lookup: { object: 'Account' } }
      ],
      defaults: [{ value: 'x' }, { target: 'Record.Title', value: 'Ms' }],
      match: { by: 'nothing' }
    });
    expect(document.columns).toEqual([{ source: 'a', target: 'Record.Email' }]);
    expect(document.defaults).toEqual([{ target: 'Record.Title', value: 'Ms' }]);
    expect(document.match).toBeUndefined();
    expect(skipped).toBe(5);
  });

  it('reads unreadable text as an empty map', () => {
    expect(parseMap('{oops').document.columns).toEqual([]);
    expect(parseMap(null).document.from.kind).toBe('columns');
  });

  it('round-trips: what it writes reads back the same', () => {
    FIXTURE.valid.forEach((each) => {
      const first = parseMap(each.document).document;
      const written = serialize(first);
      const again = parseMap(written).document;
      expect(again).toEqual(first);
      expect(serialize(again)).toBe(written);
    });
  });

  it('leaves guesses and empty steps and defaults out of what it writes', () => {
    const written = JSON.parse(
      serialize({
        columns: [{ source: 'a', target: 'Record.Email', guessed: true, transforms: [] }],
        defaults: [{ target: 'Record.Title', value: '' }]
      })
    );
    expect(written.columns).toEqual([{ source: 'a', target: 'Record.Email' }]);
    expect(written.defaults).toEqual([]);
    expect(written.version).toBe(VERSION);
  });

  it('refuses too many columns and too long a fixed value', () => {
    const many = Array.from({ length: MAX_COLUMNS + 1 }, (v, i) => ({
      source: `c${i}`,
      target: `Record.F${i}`
    }));
    expect(problems({ version: 4, columns: many }).map((p) => p.code)).toContain('tooManyColumns');
    expect(
      problems({ version: 4, columns: [{ value: 'x'.repeat(256), target: 'Record.Title' }] })
    ).toEqual([{ code: 'valueTooLong', args: [1, 255] }]);
  });
});

describe('preview checks', () => {
  const fields = {
    'Record.LastName': { label: 'Last Name', dataType: 'string', length: 5, required: true },
    'Record.Amount__c': { label: 'Amount', dataType: 'currency' },
    'Record.Birthdate': { label: 'Birthdate', dataType: 'date' },
    'Record.Active__c': { label: 'Active', dataType: 'boolean' },
    'Record.Status__c': {
      label: 'Status',
      dataType: 'picklist',
      picklistValues: [{ value: 'Open', label: 'Open' }]
    },
    'Record.Tags__c': {
      label: 'Tags',
      dataType: 'multipicklist',
      picklistValues: [{ value: 'A', label: 'A' }]
    },
    'Record.AccountId': { label: 'Account', dataType: 'reference' },
    'Record.Title': { label: 'Title', dataType: 'string', required: true }
  };

  it('flags each kind of problem', () => {
    expect(checkValue('', fields['Record.LastName'])).toEqual(['required']);
    expect(checkValue('Smithers', fields['Record.LastName'])).toEqual(['tooLong']);
    expect(checkValue('1,200.50', fields['Record.Amount__c'])).toEqual([]);
    expect(checkValue('lots', fields['Record.Amount__c'])).toEqual(['notNumber']);
    expect(checkValue('2026-02-30', fields['Record.Birthdate'])).toEqual(['notDate']);
    expect(checkValue('2026-02-28', fields['Record.Birthdate'])).toEqual([]);
    expect(checkValue('2026-02-28T10:00:00Z', { dataType: 'datetime' })).toEqual([]);
    expect(checkValue('maybe', fields['Record.Active__c'])).toEqual(['notBoolean']);
    expect(checkValue('Yes', fields['Record.Active__c'])).toEqual([]);
    expect(checkValue('Closed', fields['Record.Status__c'])).toEqual(['notInList']);
    expect(checkValue('open', fields['Record.Status__c'])).toEqual([]);
    expect(checkValue('A;B', fields['Record.Tags__c'])).toEqual(['notInList']);
    expect(checkValue('anything', undefined)).toEqual([]);
  });

  const document = {
    columns: [
      { source: 'last', target: 'Record.LastName' },
      { source: 'amount', target: 'Record.Amount__c' },
      { source: 'org', target: 'Record.AccountId', lookup: { object: 'Account', field: 'Name' } },
      { source: 'note', target: 'notes', required: true }
    ]
  };
  const samples = [
    {
      values: [
        { target: 'Record.LastName', value: 'Lee' },
        { target: 'Record.Amount__c', value: 'ten' },
        { target: 'Record.AccountId', value: 'Acme', lookup: 'none' },
        { target: 'notes', value: '' },
        { target: 'Record.Description', value: 'From the default' }
      ]
    },
    {
      values: [
        { target: 'Record.LastName', value: '' },
        { target: 'Record.Amount__c', value: '5' },
        { target: 'Record.AccountId', value: 'Bolt', lookup: 'several' },
        { target: 'notes', value: 'hi' }
      ]
    }
  ];

  it('builds the record a sample produces, with flags and unfilled required fields', () => {
    const rows = previewRows(document, fields, samples[0]);
    expect(rows.map((row) => [row.label, row.value, row.flags])).toEqual([
      ['Last Name', 'Lee', []],
      ['Amount', 'ten', ['notNumber']],
      ['Account', 'Acme', ['lookupNone']],
      ['notes', '', ['required']],
      ['Record.Description', 'From the default', []],
      ['Title', '', ['required']]
    ]);
  });

  it('summarizes Check Before Running by field', () => {
    expect(summarize(document, fields, samples)).toEqual([
      { target: 'Record.LastName', label: 'Last Name', flags: { required: 1 }, samples: [2] },
      { target: 'Record.Amount__c', label: 'Amount', flags: { notNumber: 1 }, samples: [1] },
      {
        target: 'Record.AccountId',
        label: 'Account',
        flags: { lookupNone: 1, lookupSeveral: 1 },
        samples: [1, 2]
      },
      { target: 'notes', label: 'notes', flags: { required: 1 }, samples: [1] },
      { target: 'Record.Title', label: 'Title', flags: { required: 2 }, samples: [1, 2] }
    ]);
  });
});

describe('sentences', () => {
  const words = {
    gets: '{0} gets {1}',
    fixed: '{0} is always {1}',
    then: ', then {0}',
    end: '.',
    steps: { trim: 'trimmed', lower: 'lower case' }
  };

  it('reads a column as one sentence', () => {
    expect(
      columnSentence(
        'Email',
        'profile, email',
        { source: 'profile.email', transforms: [{ op: 'trim' }, { op: 'lower' }] },
        words
      )
    ).toBe('Email gets profile, email, then trimmed, then lower case.');
    expect(columnSentence('Status', '', { value: 'subscribed' }, words)).toBe(
      'Status is always subscribed.'
    );
  });
});

describe('Super Importer: Save as Map and Use a Saved Map', () => {
  const mapping = JSON.stringify({
    version: 2,
    columns: [
      { source: 'Email', target: 'Record.Email', transforms: [{ op: 'trim' }] },
      { source: 'Notes', target: 'Ignore' },
      { source: 'Org', target: 'Record.AccountId', lookupField: 'Name' },
      { source: 'Phone', target: 'Record.Phone', blankClears: true }
    ],
    defaults: [],
    skipRows: [{ column: 'Email', test: 'blank' }]
  });

  it('saves the mapping as a map without Do Not Load columns or row rules', () => {
    const map = fromImportMapping(mapping, 'Contact', ['Ignore']);
    expect(map.to).toEqual({ kind: 'record', object: 'Contact' });
    expect(map.from).toEqual({ kind: 'columns' });
    expect(map.columns.map((column) => column.target)).toEqual([
      'Record.Email',
      'Record.AccountId',
      'Record.Phone'
    ]);
    expect(map.skipRows).toBeUndefined();
    expect(problems(map)).toEqual([]);
    expect(fromImportMapping(mapping, '', []).to).toEqual({ kind: 'record' });
  });

  it('copies a map onto the file by column name and counts what it could not use', () => {
    const map = {
      columns: [
        { source: 'email', target: 'Record.Email', transforms: [{ op: 'lower' }] },
        {
          source: 'Org',
          target: 'Record.AccountId',
          lookup: { object: 'Account', field: 'Code__c' }
        },
        { source: 'Missing', target: 'Record.Title' },
        { source: 'Phone', target: 'Record.Fax' },
        { value: 'x', target: 'Record.Department' }
      ]
    };
    const file = [
      { source: 'Email', target: 'Ignore', guessed: true },
      { source: 'Org', target: 'Ignore' },
      { source: 'Phone', target: 'Record.Phone' },
      { source: 'Other', target: 'Record.Other' }
    ];
    const result = applyToColumns(
      file,
      map,
      ['Record.Email', 'Record.AccountId', 'Record.Title', 'Record.Phone'],
      { 'Record.AccountId': ['Id', 'Name'] }
    );
    expect(result.applied).toBe(2);
    expect(result.missing).toBe(1);
    expect(result.unusable).toBe(2);
    expect(result.columns[0]).toEqual({
      source: 'Email',
      target: 'Record.Email',
      transforms: [{ op: 'lower' }],
      guessed: false,
      blankClears: false,
      lookupField: undefined
    });
    expect(result.columns[1].lookupField).toBeUndefined();
    expect(result.columns[2]).toBe(file[2]);
    expect(result.columns[3]).toBe(file[3]);
    const offered = applyToColumns(file, map, ['Record.AccountId'], {
      'Record.AccountId': ['Code__c']
    });
    expect(offered.columns[1].lookupField).toBe('Code__c');
  });
});

describe("Super Importer's Check Columns drawn by the Mapper (MAP-05)", () => {
  const file = [
    { key: 'Email', source: 'Email', target: 'Record.Email', guessed: true, examples: [] },
    { key: 'Notes', source: 'Notes', target: 'Ignore', transforms: [{ op: 'trim' }] },
    { key: 'Org', source: 'Org', target: 'Record.AccountId', lookupField: 'Name' },
    { key: 'Id', source: 'Id', target: 'Record.Id', lookupField: 'Id', blankClears: true }
  ];

  it('reads the columns as a map, guesses kept and Do Not Load left out', () => {
    const map = fromImportColumns(file, 'Contact', ['Ignore']);
    expect(map.to).toEqual({ kind: 'record', object: 'Contact' });
    expect(map.columns).toEqual([
      { source: 'Email', target: 'Record.Email', guessed: true },
      { source: 'Org', target: 'Record.AccountId', lookupField: 'Name' },
      { source: 'Id', target: 'Record.Id', blankClears: true }
    ]);
    // The Mapper reads it back with the guess still to check; what is stored leaves it out.
    expect(parseMap(map).document.columns[0].guessed).toBe(true);
    expect(JSON.parse(serialize(map)).columns[0].guessed).toBeUndefined();
  });

  it('writes the map back: a column it does not name is Do Not Load', () => {
    const columns = toImportColumns(
      file,
      { columns: [{ source: 'notes', target: 'Record.Description', blankClears: true }] },
      'Ignore'
    );
    expect(columns.map((column) => column.target)).toEqual([
      'Ignore',
      'Record.Description',
      'Ignore',
      'Ignore'
    ]);
    expect(columns[1]).toEqual({
      key: 'Notes',
      source: 'Notes',
      target: 'Record.Description',
      transforms: [],
      lookupField: undefined,
      blankClears: true,
      guessed: false
    });
    expect(columns[0].guessed).toBe(false);
  });
});

describe("Super Transformer's Apply a Map (MAP-06)", () => {
  const map = (columns, defaults = []) => ({
    version: 4,
    from: { kind: 'record', object: 'Contact' },
    to: { kind: 'record', object: 'Contact' },
    columns,
    defaults
  });
  const FIELDS = ['Title', 'Department', 'Description', 'AccountId'];

  it('turns each column into the change Super Transformer makes', () => {
    const result = toChanges(
      map(
        [
          { value: 'Volunteer', target: 'Record.Title' },
          { source: 'Description', target: 'Record.Department', transforms: [{ op: 'trim' }] },
          { source: 'Title', target: 'Record.Description' },
          { source: 'Department', target: 'Record.department', transforms: [{ op: 'upper' }] }
        ],
        [{ target: 'Record.Description', value: 'None' }]
      ),
      'Contact',
      FIELDS,
      5
    );
    expect(result).toEqual({
      changes: [
        { field: 'Title', action: 'set', value: 'Volunteer' },
        {
          field: 'Department',
          action: 'copy',
          source: 'Description',
          transforms: [{ op: 'trim' }]
        },
        {
          field: 'Description',
          action: 'copy',
          source: 'Title',
          transforms: [{ op: 'ifBlank', value: 'None' }]
        },
        { field: 'Department', action: 'transform', transforms: [{ op: 'upper' }] }
      ],
      skipped: 0,
      wrongKind: false
    });
  });

  it('leaves out what it cannot change and counts it, past five changes too', () => {
    const result = toChanges(
      map(
        [
          { source: 'Account.Name', target: 'Record.Title' },
          { source: 'Name', target: 'Record.AccountId', lookupField: 'Name' },
          { source: 'Title', target: 'Record.Title' },
          { source: 'Title', target: 'Record.OwnerId' },
          { value: 'a', target: 'Record.Title' },
          { value: 'b', target: 'Record.Department' }
        ],
        [
          { target: 'Record.Description', value: 'None' },
          { target: 'Record.Fax', value: '0' }
        ]
      ),
      'contact',
      FIELDS,
      2
    );
    expect(result.changes).toEqual([
      { field: 'Title', action: 'set', value: 'a' },
      { field: 'Department', action: 'set', value: 'b' }
    ]);
    expect(result.skipped).toBe(6);
  });

  it('refuses a map from or to another kind of record', () => {
    expect(toChanges({ ...map([]), to: { kind: 'json' } }, 'Contact', FIELDS, 5).wrongKind).toBe(
      true
    );
    expect(toChanges(map([]), 'Account', FIELDS, 5).wrongKind).toBe(true);
  });
});
