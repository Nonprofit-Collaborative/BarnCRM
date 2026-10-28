import {
  kindCards,
  templatesOfKind,
  firstTemplateOfKind,
  createsText,
  isGiftTemplate
} from '../importKinds';

jest.mock(
  '@salesforce/label/c.Core_Import_CreatesSummary',
  () => ({ default: 'This file can create: {0}.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_Import_LoadsSummary', () => ({ default: 'Loads: {0}' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_Import_LoadsRelatedSummary',
  () => ({ default: 'Loads: {0} (and {1})' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_Import_DeletesSummary', () => ({ default: 'Deletes: {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Import_CreatesPeople', () => ({ default: 'people' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_Import_CreatesOrganizations',
  () => ({ default: 'organizations' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_Import_CreatesAffiliations',
  () => ({ default: 'links between people and organizations' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_Import_CreatesGifts', () => ({ default: 'gifts' }), {
  virtual: true
});

function mapping(...targets) {
  return JSON.stringify({
    version: 1,
    columns: targets.map((target, index) => ({ source: `Column ${index}`, target }))
  });
}

const PEOPLE = { id: 'a01', mapping: mapping('Contact1.Email', 'Household.Name') };
const ORGANIZATIONS = { id: 'a02', mapping: mapping('Organization.Name') };
const GIFTS = { id: 'a03', mapping: mapping('Contact1.Email', 'Gift.Amount') };
const SESSIONS = {
  id: 'a04',
  mapping: mapping('Record.Name'),
  targetObject: 'Program_Session__c',
  targetObjectLabel: 'Program Session',
  loadOperation: 'Insert'
};

describe('the first step of the import wizard (D-136)', () => {
  it('offers Gifts only when a template maps the Gift entity', () => {
    const keys = (templates, canDelete) => kindCards(templates, canDelete).map((c) => c.key);
    expect(keys([PEOPLE, SESSIONS], false)).toEqual(['people', 'object', 'related', 'templates']);
    expect(keys([PEOPLE, GIFTS], false)).toEqual([
      'people',
      'gifts',
      'object',
      'related',
      'templates'
    ]);
  });

  it('offers the Delete card only to holders of Bulk Delete Records, with a warning', () => {
    const cards = kindCards([PEOPLE], true);
    expect(cards.map((c) => c.key)).toEqual(['people', 'object', 'related', 'delete', 'templates']);
    expect(cards.find((c) => c.key === 'delete').warning).toBe(true);
    expect(kindCards([PEOPLE], false).some((c) => c.key === 'delete')).toBe(false);
  });

  it('sorts templates into people, gifts and all', () => {
    const all = [PEOPLE, ORGANIZATIONS, GIFTS, SESSIONS];
    expect(templatesOfKind(all, 'people')).toEqual([PEOPLE, ORGANIZATIONS]);
    expect(templatesOfKind(all, 'gifts')).toEqual([GIFTS]);
    expect(templatesOfKind(all, 'templates')).toEqual(all);
    expect(isGiftTemplate({ ...SESSIONS, mapping: mapping('Gift.Amount') })).toBe(false);
  });

  it('starts People on the general template, else the first offered', () => {
    const general = { ...PEOPLE, id: 'a09', templateKey: 'generic_contact_list' };
    expect(firstTemplateOfKind([ORGANIZATIONS, general, GIFTS], 'people')).toBe(general);
    expect(firstTemplateOfKind([ORGANIZATIONS, GIFTS], 'people')).toBe(ORGANIZATIONS);
    expect(firstTemplateOfKind([PEOPLE, GIFTS], 'gifts')).toBe(GIFTS);
    expect(firstTemplateOfKind([PEOPLE], 'gifts')).toBeUndefined();
  });

  it('says what each template creates from its mapping', () => {
    expect(createsText(ORGANIZATIONS)).toBe('This file can create: organizations.');
    expect(createsText({ mapping: mapping('Contact1.Email', 'Organization.Name') })).toBe(
      'This file can create: people, organizations, links between people and organizations.'
    );
    expect(createsText(GIFTS)).toBe('This file can create: people, gifts.');
    expect(createsText({ mapping: 'not json' })).toBe('');
    expect(createsText(undefined)).toBe('');
  });

  it('says what a one-object template loads, its related records, or what it deletes', () => {
    expect(createsText(SESSIONS)).toBe('Loads: Program Session');
    expect(createsText({ ...SESSIONS, relatedLabel: 'Session Attendee' })).toBe(
      'Loads: Program Session (and Session Attendee)'
    );
    expect(createsText(SESSIONS, 'Delete by record Id')).toBe('Deletes: Program Session');
  });
});
