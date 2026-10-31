/**
 * The AI-Readiness Export's pack (AIR-01, plan Section 6.1 item 7, D-154, admin guide
 * ai-readiness-export.md): which fields are sensitive, which fields each record file holds,
 * masking, the canonical-model JSON (`schema.json`) and the plain-language README.
 *
 * Framework-free (plan Section 9.9): no lightning or @salesforce imports. It takes the Data
 * Dictionary's described objects as they come from DataDictionaryController and the text the
 * README uses as templates, so it reads no data, calls nothing and runs anywhere.
 */

export const FORMAT = 'barncrm-ai-readiness-export';
export const FORMAT_VERSION = 1;

/** Fill rates below this share are listed in the README as data quality notes. */
export const LOW_FILL_THRESHOLD = 0.1;

/** The most fields one Find export query selects (QueryCompiler.MAX_FIELDS). */
export const FIELDS_PER_QUERY = 20;

export const HANDLING = Object.freeze({ LEAVE_OUT: 'leaveOut', MASK: 'mask', KEEP: 'keep' });

export const REASONS = Object.freeze({
  EMAIL: 'email',
  PHONE: 'phone',
  ENCRYPTED: 'encrypted',
  NAME: 'name',
  BIRTH_DATE: 'birthDate',
  ADDRESS: 'address',
  IDENTITY_NUMBER: 'identityNumber',
  PRIVATE_DETAIL: 'privateDetail',
  FREE_TEXT: 'freeText'
});

/** Types Find cannot select (QueryFieldCatalog.NEVER_OFFERED); their parts are exported. */
const NOT_EXPORTED_TYPES = new Set(['address', 'location', 'base64', 'complexvalue', 'anytype']);

/** Name fields of a person, by API name in lower case (standard and person account ones). */
const PERSON_NAMES = new Set([
  'firstname',
  'lastname',
  'middlename',
  'suffix',
  'personfirstname',
  'personlastname',
  'personmiddlename',
  'personsuffix'
]);

/** Objects whose Name field is a person's name. */
const PERSON_OBJECTS = new Set(['contact', 'lead']);

/**
 * BarnCRM's own fields that hold a person's name, by object, in lower case and without a
 * namespace prefix. A household account's Name is left unflagged: it names a family, and the
 * export needs it to group people.
 */
const NAMED_FIELDS = Object.freeze({
  contact: new Set(['preferred_name__c', 'emergency_contact_name__c']),
  account: new Set(['preferred_name__c', 'emergency_contact_name__c']),
  merge_journal__c: new Set(['merged_name__c']),
  import_row__c: new Set(['person_1_name_key__c', 'person_2_name_key__c']),
  tribute__c: new Set(['honoree_name__c', 'notification_recipient_name__c'])
});

/** An API name without its namespace prefix, when the package carries one. */
function withoutNamespace(apiName) {
  const parts = apiName.split('__');
  return parts.length > 2 ? parts.slice(1).join('__') : apiName;
}

/** True when the field is one of BarnCRM's own person name fields (NAMED_FIELDS). */
function isNamedField(objectName, fieldName) {
  const names = NAMED_FIELDS[withoutNamespace(String(objectName || '').toLowerCase())];
  return Boolean(names && names.has(withoutNamespace(fieldName)));
}

/** API name fragments, checked in order; the first that matches gives the reason. */
const NAME_PATTERNS = [
  [REASONS.BIRTH_DATE, /birth|(^|_)dob(_|$)/],
  [REASONS.ADDRESS, /street|postalcode|postal_code|zip_?code|latitude|longitude/],
  [
    REASONS.IDENTITY_NUMBER,
    /ssn|social_?security|tax_?id|taxpayer|passport|driver|bank|routing|iban|account_?number/
  ],
  [
    REASONS.PRIVATE_DETAIL,
    /gender|ethnic|(^|_)race(_|$)|religio|medical|health|diagnos|disabilit|income|salary/
  ]
];

/** A long text field: free text people write notes in. */
const LONG_TEXT = 255;

/**
 * Why a field may identify a person or hold private details, as one of REASONS, or null.
 * Worked out from the field's type and API name, as the Data Dictionary describes it
 * (`dataType` is the lower-case display type), so custom fields are caught too.
 */
export function sensitivityOf(objectName, field) {
  const type = String(field.dataType || '').toLowerCase();
  const name = String(field.fieldName || '').toLowerCase();
  if (type === 'id' || type === 'reference') {
    return null;
  }
  if (type === 'email') {
    return REASONS.EMAIL;
  }
  if (type === 'phone') {
    return REASONS.PHONE;
  }
  if (type === 'encryptedstring') {
    return REASONS.ENCRYPTED;
  }
  if (
    PERSON_NAMES.has(name) ||
    (name === 'name' && PERSON_OBJECTS.has(String(objectName).toLowerCase())) ||
    isNamedField(objectName, name)
  ) {
    return REASONS.NAME;
  }
  for (const [reason, pattern] of NAME_PATTERNS) {
    if (pattern.test(name)) {
      return reason;
    }
  }
  if (type === 'textarea' && (field.length || 0) > LONG_TEXT) {
    return REASONS.FREE_TEXT;
  }
  return null;
}

/** Every flagged field of the described objects, each with its reason and the start handling. */
export function sensitiveFields(objects) {
  const flagged = [];
  for (const object of objects) {
    for (const field of object.fields || []) {
      const reason = sensitivityOf(object.objectName, field);
      if (reason) {
        flagged.push({
          key: `${object.objectName}.${field.fieldName}`,
          objectName: object.objectName,
          objectLabel: object.objectLabel,
          fieldName: field.fieldName,
          fieldLabel: field.fieldLabel,
          reason,
          handling: HANDLING.LEAVE_OUT
        });
      }
    }
  }
  return flagged;
}

/** Whether Find's export can select this field. */
export function isExportable(field) {
  return !NOT_EXPORTED_TYPES.has(String(field.dataType || '').toLowerCase());
}

/**
 * What the pack does with a field: its chosen HANDLING, Leave Out for a flagged field with no
 * choice, and null for a field not flagged. `handlingByKey` maps `Object.Field` to HANDLING.
 */
function handlingOf(object, field, handlingByKey) {
  if (!sensitivityOf(object.objectName, field)) {
    return null;
  }
  return handlingByKey[`${object.objectName}.${field.fieldName}`] || HANDLING.LEAVE_OUT;
}

/**
 * The fields one object's record file holds, in the dictionary's order with Id first: every
 * field Find can select that is not left out.
 */
export function recordFields(object, handlingByKey = {}) {
  const names = ['Id'];
  for (const field of object.fields || []) {
    const handling = handlingOf(object, field, handlingByKey);
    if (field.fieldName !== 'Id' && isExportable(field) && handling !== HANDLING.LEAVE_OUT) {
      names.push(field.fieldName);
    }
  }
  return names;
}

/**
 * The fields split into Find export queries of at most FIELDS_PER_QUERY each, every query
 * holding Id so the pieces of a record can be joined.
 */
export function queryChunks(fieldNames, size = FIELDS_PER_QUERY) {
  const rest = fieldNames.filter((name) => name !== 'Id');
  const chunks = [];
  for (let start = 0; start < rest.length; start += size - 1) {
    chunks.push(['Id', ...rest.slice(start, start + size - 1)]);
  }
  return chunks.length ? chunks : [['Id']];
}

/** Lower-case hexadecimal of bytes. */
function hex(bytes) {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

/**
 * A masker: `mask(value)` resolves to `masked-` and ten hexadecimal characters of the keyed
 * hash of the value, the same for the same value, or to null for an empty value. `sign(text)`
 * resolves to the hash bytes; the browser's is an HMAC-SHA-256 under a key made for one pack
 * (see `browserSigner`), so codes cannot be reversed or compared across packs.
 */
export function createMasker(sign) {
  const known = new Map();
  return async function mask(value) {
    if (value === null || value === undefined || value === '') {
      return null;
    }
    const text = typeof value === 'object' ? JSON.stringify(value) : String(value);
    if (!known.has(text)) {
      known.set(text, `masked-${hex(new Uint8Array(await sign(text))).slice(0, 10)}`);
    }
    return known.get(text);
  };
}

/** The browser's signer: HMAC-SHA-256 under a random key that is never written anywhere. */
export async function browserSigner(subtle = globalThis.crypto && globalThis.crypto.subtle) {
  const key = await subtle.generateKey({ name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const encoder = new TextEncoder();
  return (text) => subtle.sign('HMAC', key, encoder.encode(text));
}

/** A described value as JSON: blank text and absent values become null. */
function orNull(value) {
  return value === undefined || value === null || value === '' ? null : value;
}

function listOf(text, separator) {
  return text
    ? String(text)
        .split(separator)
        .map((part) => part.trim())
        .filter(Boolean)
    : [];
}

/**
 * The canonical-model JSON document (`schema.json`), as admin guide ai-readiness-export.md
 * documents it.
 *
 * @param {Array} objects described objects, each { objectName, objectLabel, isCustom, fields }
 * @param {object} options `handlingByKey` (Object.Field to HANDLING), `fillRates` (Object to a
 *   Map of field to share), `records` (Object to { file, count, stopped }), `checks` (the Data
 *   Quality results), `createdAt` (a Date)
 */
export function buildSchema(objects, options = {}) {
  const handlingByKey = options.handlingByKey || {};
  const fillRates = options.fillRates || {};
  const records = options.records || {};
  const relationships = [];
  const schemaObjects = objects.map((object) => {
    const shares = fillRates[object.objectName];
    const recordInfo = records[object.objectName];
    const inFile = recordInfo ? new Set(recordFields(object, handlingByKey)) : new Set();
    return {
      apiName: object.objectName,
      label: object.objectLabel,
      custom: Boolean(object.isCustom),
      recordFile: recordInfo ? recordInfo.file : null,
      recordCount: recordInfo ? recordInfo.count : null,
      recordsStoppedAtLimit: recordInfo ? Boolean(recordInfo.stopped) : null,
      fields: (object.fields || []).map((field) => {
        const relatedTo = listOf(field.relatedTo, ',');
        if (relatedTo.length) {
          relationships.push({ object: object.objectName, field: field.fieldName, relatedTo });
        }
        const share = shares && shares.has(field.fieldName) ? shares.get(field.fieldName) : null;
        return {
          apiName: field.fieldName,
          label: field.fieldLabel,
          type: field.dataType,
          length: orNull(field.length),
          precision: orNull(field.precision),
          required: Boolean(field.required),
          unique: Boolean(field.isUnique),
          externalId: Boolean(field.externalId),
          custom: Boolean(field.isCustom),
          picklistValues: listOf(field.picklistValues, ';'),
          helpText: orNull(field.helpText),
          formula: orNull(field.formula),
          relatedTo,
          fillRate: share === null ? null : Math.round(share * 1000) / 1000,
          sensitive: sensitivityOf(object.objectName, field),
          handling: handlingOf(object, field, handlingByKey),
          inRecordFile: inFile.has(field.fieldName)
        };
      })
    };
  });
  return {
    format: FORMAT,
    formatVersion: FORMAT_VERSION,
    createdAt: (options.createdAt || new Date()).toISOString(),
    objects: schemaObjects,
    relationships,
    dataQuality: {
      lowFillThreshold: LOW_FILL_THRESHOLD,
      checks: (options.checks || [])
        .filter((check) => !check.errorMessage && check.count !== null && check.count !== undefined)
        .map((check) => ({
          key: check.key,
          title: check.title,
          description: orNull(check.description),
          count: check.count
        }))
    }
  };
}

/** A label with `{0}`, `{1}` and so on replaced by the values, in order. */
function fill(template, ...values) {
  return values.reduce(
    (text, value, index) => text.split(`{${index}}`).join(String(value)),
    String(template)
  );
}

function fieldList(schema, test) {
  const names = [];
  for (const object of schema.objects) {
    for (const field of object.fields) {
      if (test(field)) {
        names.push(`${object.apiName}.${field.apiName}`);
      }
    }
  }
  return names.join(', ');
}

/**
 * The README (`README.md`) for a schema document, in plain language. `text` holds the custom
 * label templates by the keys used below, so the module names no wording of its own.
 */
export function buildReadme(schema, text) {
  const lines = [`# ${text.title}`, '', fill(text.intro, schema.createdAt.slice(0, 10)), ''];
  const hasRecords = schema.objects.some((object) => object.recordFile);

  lines.push(`## ${text.filesHeading}`, '', `- ${text.fileSchema}`, `- ${text.fileDictionary}`);
  if (hasRecords) {
    lines.push(`- ${text.fileData}`);
  }
  lines.push('', `## ${text.objectsHeading}`, '');
  for (const object of schema.objects) {
    lines.push(
      object.recordFile
        ? `- ${fill(text.objectWithRecords, object.label, object.apiName, object.fields.length, object.recordCount, object.recordFile)}`
        : `- ${fill(text.objectLine, object.label, object.apiName, object.fields.length)}`
    );
    if (object.recordsStoppedAtLimit) {
      lines.push(`  - ${text.objectStopped}`);
    }
  }

  if (schema.relationships.length) {
    lines.push('', `## ${text.relationshipsHeading}`, '');
    for (const link of schema.relationships) {
      lines.push(
        `- ${fill(text.relationshipLine, `${link.object}.${link.field}`, link.relatedTo.join(', '))}`
      );
    }
  }

  lines.push('', `## ${text.privacyHeading}`, '');
  const byHandling = (handling) => fieldList(schema, (field) => field.handling === handling);
  const leftOut = byHandling(HANDLING.LEAVE_OUT);
  const masked = byHandling(HANDLING.MASK);
  const kept = byHandling(HANDLING.KEEP);
  if (!leftOut && !masked && !kept) {
    lines.push(text.privacyNone);
  }
  if (leftOut) {
    lines.push(`- ${fill(text.privacyLeftOut, leftOut)}`);
  }
  if (masked) {
    lines.push(`- ${fill(text.privacyMasked, masked)}`);
  }
  if (kept) {
    lines.push(`- ${fill(text.privacyKept, kept)}`);
  }
  lines.push('', text.privacyAdvice);

  lines.push('', `## ${text.qualityHeading}`, '');
  const lowFill = fieldList(
    schema,
    (field) => field.fillRate !== null && field.fillRate < schema.dataQuality.lowFillThreshold
  );
  if (lowFill) {
    lines.push(
      `- ${fill(text.qualityLowFill, Math.round(schema.dataQuality.lowFillThreshold * 100), lowFill)}`
    );
  }
  for (const check of schema.dataQuality.checks) {
    lines.push(`- ${fill(text.qualityCheck, check.title, check.count)}`);
  }
  if (!lowFill && !schema.dataQuality.checks.length) {
    lines.push(text.qualityNone);
  }

  lines.push('', `## ${text.useHeading}`, '');
  [text.useStep1, text.useStep2, text.useStep3, text.useStep4].forEach((step, index) => {
    lines.push(`${index + 1}. ${step}`);
  });
  return `${lines.join('\n')}\n`;
}
