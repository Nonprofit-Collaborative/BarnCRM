/**
 * What a submission writes (canonical model 29ZW R-FM1, 29ZY; ADR-NEXT `NEXT-forms-module.md`,
 * decision 6): each record entry with the field values the counted answers give it, its
 * constants, and its links. Framework-free (plan 9.9). The builder's preview shows this plan;
 * `FormSubmitService` in Apex builds the same plan from the published version and writes it.
 */

import { allFields, objectOf, CONTEXT_LINK } from 'c/formDefinition';

/** The order records are written in: the person and organization first, then the rest. */
const KIND_ORDER = { person: 0, organization: 1, related: 2 };

/**
 * The records a submission writes, in the order they are written. Each is
 * `{ key, kind, object, fields, links, matching }`: `fields` holds the mapped answers (a blank
 * answer is left out, so a match keeps what it has) and the constants, by field API name.
 *
 * @param definition the published definition
 * @param counted the counted answers (`countedAnswers` in c/formRules)
 */
export function planWrites(definition, counted) {
  const answers = counted || {};
  const records = ((definition && definition.records) || []).map((record) => ({
    key: record.key,
    kind: record.kind,
    object: objectOf(record),
    fields: { ...(record.values || {}) },
    links: { ...(record.links || {}) },
    matching: record.matching || null
  }));
  const byKey = new Map(records.map((record) => [record.key, record]));
  allFields(definition).forEach((field) => {
    const record = field.target && byKey.get(field.target.record);
    if (record && field.target.field && answers[field.key] !== undefined) {
      record.fields[field.target.field] = answers[field.key];
    }
  });
  return records
    .map((record, index) => ({ record, index }))
    .sort((a, b) => KIND_ORDER[a.record.kind] - KIND_ORDER[b.record.kind] || a.index - b.index)
    .map(({ record }) => record);
}

/** The questions mapped to each record entry, by record key, for the builder's summary. */
export function questionsByRecord(definition) {
  const byRecord = {};
  allFields(definition).forEach((field) => {
    if (field.target && field.target.record) {
      (byRecord[field.target.record] = byRecord[field.target.record] || []).push(field);
    }
  });
  return byRecord;
}

/**
 * Whether a record entry links to the record the form is filled from, so the runner can say a
 * form needs one (a registration form filled from an event).
 */
export function needsContext(definition) {
  return ((definition && definition.records) || []).some((record) =>
    Object.values(record.links || {}).includes(CONTEXT_LINK)
  );
}
