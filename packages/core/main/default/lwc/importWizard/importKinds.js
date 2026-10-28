import kindPeopleTitle from '@salesforce/label/c.Core_Import_KindPeopleTitle';
import kindPeopleText from '@salesforce/label/c.Core_Import_KindPeopleText';
import kindGiftsTitle from '@salesforce/label/c.Core_Import_KindGiftsTitle';
import kindGiftsText from '@salesforce/label/c.Core_Import_KindGiftsText';
import kindObjectTitle from '@salesforce/label/c.Core_Import_KindObjectTitle';
import kindObjectText from '@salesforce/label/c.Core_Import_KindObjectText';
import kindRelatedTitle from '@salesforce/label/c.Core_Import_KindRelatedTitle';
import kindRelatedText from '@salesforce/label/c.Core_Import_KindRelatedText';
import kindDeleteTitle from '@salesforce/label/c.Core_Import_KindDeleteTitle';
import kindDeleteText from '@salesforce/label/c.Core_Import_KindDeleteText';
import kindTemplatesTitle from '@salesforce/label/c.Core_Import_KindTemplatesTitle';
import kindTemplatesText from '@salesforce/label/c.Core_Import_KindTemplatesText';
import createsSummary from '@salesforce/label/c.Core_Import_CreatesSummary';
import loadsSummary from '@salesforce/label/c.Core_Import_LoadsSummary';
import loadsRelatedSummary from '@salesforce/label/c.Core_Import_LoadsRelatedSummary';
import deletesSummary from '@salesforce/label/c.Core_Import_DeletesSummary';
import createsPeople from '@salesforce/label/c.Core_Import_CreatesPeople';
import createsSecondPerson from '@salesforce/label/c.Core_Import_CreatesSecondPerson';
import createsHouseholds from '@salesforce/label/c.Core_Import_CreatesHouseholds';
import createsOrganizations from '@salesforce/label/c.Core_Import_CreatesOrganizations';
import createsAffiliations from '@salesforce/label/c.Core_Import_CreatesAffiliations';
import createsGifts from '@salesforce/label/c.Core_Import_CreatesGifts';
import createsAllocations from '@salesforce/label/c.Core_Import_CreatesAllocations';
import createsSoftCredits from '@salesforce/label/c.Core_Import_CreatesSoftCredits';
import createsTributes from '@salesforce/label/c.Core_Import_CreatesTributes';
import { DELETE } from 'c/importLoadOptions';

/**
 * The choices of the import wizard's first step, "What Are You Importing?" (D-136), and what a
 * template creates, read from its mapping.
 *
 * Core names no module object here: a gift template is one whose mapping has a column for the
 * `Gift` row entity, which Core stages and an installed module loads (R-IR6).
 */
export const KIND_PEOPLE = 'people';
export const KIND_GIFTS = 'gifts';
export const KIND_OBJECT = 'object';
export const KIND_RELATED = 'related';
export const KIND_DELETE = 'delete';
export const KIND_TEMPLATES = 'templates';

/** The choices that make a new one-object template before going on. */
export const OBJECT_KINDS = [KIND_OBJECT, KIND_RELATED, KIND_DELETE];

const GIFT_ENTITY = 'Gift';

/** What each row entity creates, in the order the summary lists them. */
const ENTITY_KINDS = [
  ['Contact1', createsPeople],
  ['Contact2', createsSecondPerson],
  ['Household', createsHouseholds],
  ['Organization', createsOrganizations],
  ['Affiliation', createsAffiliations],
  [GIFT_ENTITY, createsGifts],
  ['Allocation', createsAllocations],
  ['SoftCredit', createsSoftCredits],
  ['Tribute', createsTributes]
];

function format(label, ...values) {
  return values.reduce((text, value, index) => text.replace(`{${index}}`, value), label);
}

/** The row entities a template's columns load, from its saved mapping. */
function entitiesOf(template) {
  const entities = new Set();
  try {
    const parsed = JSON.parse((template && template.mapping) || '{}');
    (parsed.columns || []).forEach((column) => {
      const target = String(column.target || '');
      if (target.includes('.')) {
        entities.add(target.split('.')[0]);
      }
    });
  } catch {
    // A mapping that does not read says nothing about what it creates.
  }
  return entities;
}

export function isGiftTemplate(template) {
  return !template.targetObject && entitiesOf(template).has(GIFT_ENTITY);
}

/** The templates a choice offers: people files, gift files, or every template. */
export function templatesOfKind(templates, kind) {
  if (kind === KIND_PEOPLE) {
    return templates.filter((each) => !each.targetObject && !isGiftTemplate(each));
  }
  if (kind === KIND_GIFTS) {
    return templates.filter(isGiftTemplate);
  }
  return templates;
}

/**
 * The cards of the first step: Gifts only when a template loads gifts, Delete only for holders
 * of Bulk Delete Records.
 */
export function kindCards(templates, canDelete) {
  const cards = [{ key: KIND_PEOPLE, title: kindPeopleTitle, text: kindPeopleText }];
  if (templates.some(isGiftTemplate)) {
    cards.push({ key: KIND_GIFTS, title: kindGiftsTitle, text: kindGiftsText });
  }
  cards.push({ key: KIND_OBJECT, title: kindObjectTitle, text: kindObjectText });
  cards.push({ key: KIND_RELATED, title: kindRelatedTitle, text: kindRelatedText });
  if (canDelete) {
    cards.push({ key: KIND_DELETE, title: kindDeleteTitle, text: kindDeleteText, warning: true });
  }
  cards.push({ key: KIND_TEMPLATES, title: kindTemplatesTitle, text: kindTemplatesText });
  return cards;
}

/**
 * What a template creates (D-136): for one object, the object (and its related records) or
 * what it deletes; for people and gifts, each kind of record its columns load. A person and an
 * organization on one row are linked, so both mean links between them too.
 */
export function createsText(template, operation) {
  if (!template) {
    return '';
  }
  if (template.targetObject) {
    const name = template.targetObjectLabel || template.targetObject;
    if ((operation || template.loadOperation) === DELETE) {
      return format(deletesSummary, name);
    }
    return template.relatedLabel
      ? format(loadsRelatedSummary, name, template.relatedLabel)
      : format(loadsSummary, name);
  }
  const entities = entitiesOf(template);
  if (entities.has('Contact1') && entities.has('Organization')) {
    entities.add('Affiliation');
  }
  const kinds = ENTITY_KINDS.filter(([entity]) => entities.has(entity)).map(([, text]) => text);
  return kinds.length > 0 ? format(createsSummary, kinds.join(', ')) : '';
}
