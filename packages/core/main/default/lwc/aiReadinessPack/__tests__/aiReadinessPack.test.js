import { TextEncoder as NodeTextEncoder } from 'util';
import {
  FORMAT,
  HANDLING,
  REASONS,
  sensitivityOf,
  sensitiveFields,
  recordFields,
  queryChunks,
  createMasker,
  browserSigner,
  buildSchema,
  buildReadme
} from 'c/aiReadinessPack';

// jsdom has no TextEncoder; the browser and Node have one.
global.TextEncoder = global.TextEncoder || NodeTextEncoder;

const field = (fieldName, dataType = 'string', extra = {}) => ({
  fieldName,
  fieldLabel: fieldName,
  dataType,
  ...extra
});

const CONTACT = {
  objectName: 'Contact',
  objectLabel: 'Contact',
  isCustom: false,
  fields: [
    field('Id', 'id'),
    field('AccountId', 'reference', { relatedTo: 'Account' }),
    field('Birthdate', 'date'),
    field('Email', 'email'),
    field('LastName', 'string', { required: true }),
    field('MailingAddress', 'address'),
    field('MailingStreet', 'textarea', { length: 255 }),
    field('Status__c', 'picklist', { picklistValues: 'Active; Lapsed', isCustom: true })
  ]
};

const README_TEXT = new Proxy(
  {},
  {
    // A heading reads [key]; any other text reads "key" and its placeholders.
    get: (target, key) => {
      const name = String(key);
      return /Heading$|^title$/.test(name) ? `[${name}]` : `${name} {0}|{1}|{2}|{3}|{4}`;
    }
  }
);

describe('c/aiReadinessPack', () => {
  it('flags fields by type and API name, and leaves ordinary and lookup fields alone', () => {
    expect(sensitivityOf('Contact', field('Email', 'email'))).toBe(REASONS.EMAIL);
    expect(sensitivityOf('Contact', field('MobilePhone', 'phone'))).toBe(REASONS.PHONE);
    expect(sensitivityOf('X__c', field('Secret__c', 'encryptedstring'))).toBe(REASONS.ENCRYPTED);
    expect(sensitivityOf('Contact', field('FirstName'))).toBe(REASONS.NAME);
    expect(sensitivityOf('Contact', field('Name'))).toBe(REASONS.NAME);
    expect(sensitivityOf('Account', field('Name'))).toBeNull();
    expect(sensitivityOf('Contact', field('Birthdate', 'date'))).toBe(REASONS.BIRTH_DATE);
    expect(sensitivityOf('X__c', field('DOB__c', 'date'))).toBe(REASONS.BIRTH_DATE);
    expect(sensitivityOf('Contact', field('MailingPostalCode'))).toBe(REASONS.ADDRESS);
    expect(sensitivityOf('X__c', field('Tax_ID__c'))).toBe(REASONS.IDENTITY_NUMBER);
    expect(sensitivityOf('X__c', field('Race__c', 'picklist'))).toBe(REASONS.PRIVATE_DETAIL);
    expect(sensitivityOf('X__c', field('Trace_Code__c'))).toBeNull();
    expect(sensitivityOf('X__c', field('Notes__c', 'textarea', { length: 32768 }))).toBe(
      REASONS.FREE_TEXT
    );
    expect(sensitivityOf('X__c', field('Short__c', 'textarea', { length: 255 }))).toBeNull();
    expect(sensitivityOf('Contact', field('ReportsToId', 'reference'))).toBeNull();
    expect(sensitivityOf('Contact', field('Status__c', 'picklist'))).toBeNull();
  });

  it('lists flagged fields with their reason, starting at Leave Out', () => {
    const flagged = sensitiveFields([CONTACT]);
    expect(flagged.map((row) => [row.key, row.reason, row.handling])).toEqual([
      ['Contact.Birthdate', REASONS.BIRTH_DATE, HANDLING.LEAVE_OUT],
      ['Contact.Email', REASONS.EMAIL, HANDLING.LEAVE_OUT],
      ['Contact.LastName', REASONS.NAME, HANDLING.LEAVE_OUT],
      ['Contact.MailingStreet', REASONS.ADDRESS, HANDLING.LEAVE_OUT]
    ]);
  });

  it('puts Id first in a record file and drops left-out, unchosen flagged and compound fields', () => {
    const fields = recordFields(CONTACT, {
      'Contact.Birthdate': HANDLING.LEAVE_OUT,
      'Contact.Email': HANDLING.KEEP,
      'Contact.LastName': HANDLING.MASK
    });
    // MailingStreet is flagged with no choice, so it is left out; MailingAddress is compound.
    expect(fields).toEqual(['Id', 'AccountId', 'Email', 'LastName', 'Status__c']);
  });

  it('splits fields into queries of at most twenty, each holding Id', () => {
    const names = ['Id', ...Array.from({ length: 40 }, (unused, index) => `F${index}`)];
    const chunks = queryChunks(names);
    expect(chunks.map((chunk) => chunk.length)).toEqual([20, 20, 3]);
    chunks.forEach((chunk) => expect(chunk[0]).toBe('Id'));
    expect(chunks.flat().filter((name) => name !== 'Id')).toHaveLength(40);
    expect(queryChunks(['Id'])).toEqual([['Id']]);
  });

  it('masks the same value to the same code, and empty values to null', async () => {
    const sign = jest.fn(async (text) => new TextEncoder().encode(`${text}-signed-value`).buffer);
    const mask = createMasker(sign);
    const first = await mask('Smith');
    expect(first).toMatch(/^masked-[0-9a-f]{10}$/);
    expect(await mask('Smith')).toBe(first);
    expect(await mask('Jones')).not.toBe(first);
    expect(await mask(null)).toBeNull();
    expect(await mask('')).toBeNull();
    expect(sign).toHaveBeenCalledTimes(2);
  });

  it('signs with an HMAC key it never exports', async () => {
    const subtle = {
      generateKey: jest.fn(async () => 'key'),
      sign: jest.fn(async () => new Uint8Array([1, 2, 3]).buffer)
    };
    const sign = await browserSigner(subtle);
    await sign('value');
    expect(subtle.generateKey).toHaveBeenCalledWith({ name: 'HMAC', hash: 'SHA-256' }, false, [
      'sign'
    ]);
    expect(subtle.sign).toHaveBeenCalledWith('HMAC', 'key', expect.anything());
    expect(Array.from(subtle.sign.mock.calls[0][2])).toEqual([118, 97, 108, 117, 101]);
  });

  it('builds the canonical-model JSON with handling, fill rates, records, relationships and checks', () => {
    const schema = buildSchema([CONTACT], {
      handlingByKey: { 'Contact.Email': HANDLING.KEEP, 'Contact.LastName': HANDLING.MASK },
      fillRates: { Contact: new Map([['Email', 0.8512]]) },
      records: { Contact: { file: 'data/Contact.csv', count: 3, stopped: false } },
      checks: [
        { key: 'a', title: 'People Without an Email', count: 4 },
        { key: 'b', title: 'Broken', errorMessage: 'No access' }
      ],
      createdAt: new Date('2026-10-31T12:00:00Z')
    });
    expect(schema.format).toBe(FORMAT);
    expect(schema.createdAt).toBe('2026-10-31T12:00:00.000Z');
    const [contact] = schema.objects;
    expect(contact.recordFile).toBe('data/Contact.csv');
    const byName = Object.fromEntries(contact.fields.map((one) => [one.apiName, one]));
    expect(byName.Email).toMatchObject({
      fillRate: 0.851,
      sensitive: 'email',
      handling: 'keep',
      inRecordFile: true
    });
    expect(byName.Birthdate).toMatchObject({ handling: 'leaveOut', inRecordFile: false });
    expect(byName.LastName).toMatchObject({ handling: 'mask', required: true, inRecordFile: true });
    expect(byName.MailingAddress).toMatchObject({ inRecordFile: false, handling: null });
    expect(byName.Status__c).toMatchObject({
      picklistValues: ['Active', 'Lapsed'],
      custom: true,
      fillRate: null,
      sensitive: null
    });
    expect(schema.relationships).toEqual([
      { object: 'Contact', field: 'AccountId', relatedTo: ['Account'] }
    ]);
    expect(schema.dataQuality.checks).toEqual([
      { key: 'a', title: 'People Without an Email', description: null, count: 4 }
    ]);
  });

  it('leaves record keys null when records were not included', () => {
    const [contact] = buildSchema([CONTACT]).objects;
    expect(contact).toMatchObject({
      recordFile: null,
      recordCount: null,
      recordsStoppedAtLimit: null
    });
    expect(contact.fields.every((one) => one.inRecordFile === false)).toBe(true);
  });

  it('writes a README naming files, objects, links, privacy choices and quality notes', () => {
    const schema = buildSchema([CONTACT], {
      handlingByKey: { 'Contact.Email': HANDLING.KEEP, 'Contact.LastName': HANDLING.MASK },
      fillRates: { Contact: new Map([['Status__c', 0.05]]) },
      records: { Contact: { file: 'data/Contact.csv', count: 3, stopped: true } },
      checks: [{ key: 'a', title: 'People Without an Email', count: 4 }],
      createdAt: new Date('2026-10-31T12:00:00Z')
    });
    const readme = buildReadme(schema, README_TEXT);
    expect(readme.startsWith('# [title]\n')).toBe(true);
    expect(readme).toContain('intro 2026-10-31|');
    expect(readme).toContain('- fileData ');
    expect(readme).toContain('objectWithRecords Contact|Contact|8|3|data/Contact.csv');
    expect(readme).toContain('  - objectStopped ');
    expect(readme).toContain('relationshipLine Contact.AccountId|Account|');
    expect(readme).toContain('privacyLeftOut Contact.Birthdate, Contact.MailingStreet|');
    expect(readme).toContain('privacyMasked Contact.LastName|');
    expect(readme).toContain('privacyKept Contact.Email|');
    expect(readme).toContain('qualityLowFill 10|Contact.Status__c|');
    expect(readme).toContain('qualityCheck People Without an Email|4|');
    expect(readme).toContain('4. useStep4');
    expect(readme).not.toContain('privacyNone');
    expect(readme).not.toContain('qualityNone');
  });

  it('says so in the README when nothing was flagged and no quality notes were included', () => {
    const plain = { objectName: 'Account', objectLabel: 'Account', fields: [field('Industry')] };
    const readme = buildReadme(buildSchema([plain]), README_TEXT);
    expect(readme).toContain('privacyNone');
    expect(readme).toContain('qualityNone');
    expect(readme).not.toContain('fileData');
    expect(readme).not.toContain('[relationshipsHeading]');
  });
});
