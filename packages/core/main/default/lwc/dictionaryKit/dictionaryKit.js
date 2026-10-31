/**
 * What the Data Dictionary (C-52, admin guide data-dictionary.md) and the AI-Readiness Export
 * (AIR-01, admin guide ai-readiness-export.md) share: the dictionary's rows, table columns and
 * CSV, and fill rates read from Field Utilization's own plan and counts, so there is one
 * dictionary file layout and one counting loop.
 */
import getPlan from '@salesforce/apex/FieldUtilizationController.getPlan';
import countFields from '@salesforce/apex/FieldUtilizationController.countFields';
import { toCsv } from 'c/findCsv';

import YES from '@salesforce/label/c.Core_DataDictionary_Yes';
import NO from '@salesforce/label/c.Core_DataDictionary_No';
import COL_OBJECT from '@salesforce/label/c.Core_DataDictionary_ColObject';
import COL_OBJECT_API_NAME from '@salesforce/label/c.Core_DataDictionary_ColObjectApiName';
import COL_FIELD from '@salesforce/label/c.Core_DataDictionary_ColField';
import COL_API_NAME from '@salesforce/label/c.Core_DataDictionary_ColApiName';
import COL_TYPE from '@salesforce/label/c.Core_DataDictionary_ColType';
import COL_LENGTH from '@salesforce/label/c.Core_DataDictionary_ColLength';
import COL_PRECISION from '@salesforce/label/c.Core_DataDictionary_ColPrecision';
import COL_REQUIRED from '@salesforce/label/c.Core_DataDictionary_ColRequired';
import COL_UNIQUE from '@salesforce/label/c.Core_DataDictionary_ColUnique';
import COL_EXTERNAL_ID from '@salesforce/label/c.Core_DataDictionary_ColExternalId';
import COL_CUSTOM from '@salesforce/label/c.Core_DataDictionary_ColCustom';
import COL_PICKLIST_VALUES from '@salesforce/label/c.Core_DataDictionary_ColPicklistValues';
import COL_HELP_TEXT from '@salesforce/label/c.Core_DataDictionary_ColHelpText';
import COL_FORMULA from '@salesforce/label/c.Core_DataDictionary_ColFormula';
import COL_RELATED_TO from '@salesforce/label/c.Core_DataDictionary_ColRelatedTo';
import COL_FILL_RATE from '@salesforce/label/c.Core_DataDictionary_ColFillRate';

const PERCENT = { maximumFractionDigits: 1 };

const isBlank = (value) => value === null || value === undefined;
const yesNo = (value) => (value ? YES : NO);

/** A fill rate as a CSV cell: one decimal and a percent sign, or empty when not counted. */
function fillRateText(share) {
  return isBlank(share) ? '' : `${Math.round(share * 1000) / 10}%`;
}

/** The table and CSV row for one described field. */
export function toRow(objectDictionary, field, share) {
  return {
    key: `${objectDictionary.objectName}|${field.fieldName}`,
    objectLabel: objectDictionary.objectLabel,
    objectName: objectDictionary.objectName,
    fieldLabel: field.fieldLabel,
    fieldName: field.fieldName,
    dataType: field.dataType,
    length: isBlank(field.length) ? null : field.length,
    precision: field.precision || '',
    required: yesNo(field.required),
    isUnique: yesNo(field.isUnique),
    externalId: yesNo(field.externalId),
    isCustom: yesNo(field.isCustom),
    picklistValues: field.picklistValues || '',
    helpText: field.helpText || '',
    formula: field.formula || '',
    relatedTo: field.relatedTo || '',
    fillRate: isBlank(share) ? null : share
  };
}

export const TABLE_COLUMNS = [
  { label: COL_OBJECT, fieldName: 'objectLabel', initialWidth: 160 },
  { label: COL_FIELD, fieldName: 'fieldLabel', initialWidth: 200 },
  { label: COL_API_NAME, fieldName: 'fieldName', initialWidth: 200 },
  { label: COL_TYPE, fieldName: 'dataType', initialWidth: 120 },
  { label: COL_LENGTH, fieldName: 'length', type: 'number', initialWidth: 90 },
  { label: COL_PRECISION, fieldName: 'precision', initialWidth: 100 },
  { label: COL_REQUIRED, fieldName: 'required', initialWidth: 90 },
  { label: COL_UNIQUE, fieldName: 'isUnique', initialWidth: 90 },
  { label: COL_EXTERNAL_ID, fieldName: 'externalId', initialWidth: 110 },
  { label: COL_CUSTOM, fieldName: 'isCustom', initialWidth: 90 },
  { label: COL_PICKLIST_VALUES, fieldName: 'picklistValues', wrapText: true, initialWidth: 260 },
  { label: COL_HELP_TEXT, fieldName: 'helpText', wrapText: true, initialWidth: 260 },
  { label: COL_FORMULA, fieldName: 'formula', wrapText: true, initialWidth: 260 },
  { label: COL_RELATED_TO, fieldName: 'relatedTo', initialWidth: 160 }
];

export const FILL_RATE_COLUMN = {
  label: COL_FILL_RATE,
  fieldName: 'fillRate',
  type: 'percent',
  typeAttributes: PERCENT,
  initialWidth: 100
};

/** The CSV's columns: the table's, with the object's API name and the fill rate as text. */
function csvColumns(withFillRates) {
  const columns = [
    { label: COL_OBJECT, path: 'objectLabel' },
    { label: COL_OBJECT_API_NAME, path: 'objectName' },
    ...TABLE_COLUMNS.slice(1).map((column) => ({ label: column.label, path: column.fieldName }))
  ];
  if (withFillRates) {
    columns.push({ label: COL_FILL_RATE, path: 'fillRateText' });
  }
  return columns;
}

/** The dictionary's CSV text for these rows, with a Fill Rate column when asked. */
export function dictionaryCsv(rows, withFillRates) {
  return toCsv(
    csvColumns(withFillRates),
    rows.map((row) => ({ ...row, fillRateText: fillRateText(row.fillRate) }))
  );
}

/**
 * Fill rates by field API name, from Field Utilization's own counting: each field's filled and
 * record totals are summed across record types.
 */
export function sharesFrom(countRows) {
  const sums = new Map();
  for (const row of countRows) {
    const sum = sums.get(row.fieldName) || { filled: 0, total: 0 };
    sum.filled += row.filled || 0;
    sum.total += row.total || 0;
    sums.set(row.fieldName, sum);
  }
  const shares = new Map();
  sums.forEach((sum, name) => {
    if (sum.total > 0) {
      shares.set(name, sum.filled / sum.total);
    }
  });
  return shares;
}

/** Counts one chunk of fields, then the next: one call at a time, so the server never runs two. */
async function countNext(objectName, names, size, start, counted, isCurrent) {
  if (start >= names.length || !isCurrent()) {
    return counted;
  }
  const chunk = await countFields({ objectName, fieldNames: names.slice(start, start + size) });
  return countNext(
    objectName,
    names,
    size,
    start + size,
    [...counted, ...(chunk.rows || [])],
    isCurrent
  );
}

/**
 * One object's fill rates, from Field Utilization's plan and counts within its limits: a Map of
 * field API name to share, or null when the object is too large to count. `isCurrent()`
 * returning false stops between calls. A failed call rejects.
 */
export async function readFillRates(objectName, isCurrent = () => true) {
  const plan = await getPlan({ objectName });
  if (plan.tooLarge) {
    return null;
  }
  const names = (plan.fields || []).map((field) => field.fieldName);
  const size = plan.chunkSize || names.length || 1;
  return sharesFrom(await countNext(objectName, names, size, 0, [], isCurrent));
}
