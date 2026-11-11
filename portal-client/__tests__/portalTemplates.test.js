/* The shipped templates (PB-03, PB-07, PB-08) checked offline against the package metadata in this
 * repository: Salesforce re-checks every call against the org, so a template that fails here
 * would be refused there. Also the person-scoped rules the templates must keep. */
import fs from 'fs';
import path from 'path';
import { checkTemplate } from '../src/portalTemplate.js';
import volunteer from '../templates/volunteer.json';
import speaker from '../templates/speaker.json';
import donor from '../templates/donor.json';
import board from '../templates/board.json';

const PACKAGES = path.join(__dirname, '..', '..', 'packages');
const BUILT_IN = ['Id', 'Name', 'CreatedDate'];
// Standard Contact fields these templates use; Core owns Contact, so the checks stop at the name.
const CONTACT_STANDARD = [
  'FirstName',
  'LastName',
  'Email',
  'Phone',
  'MobilePhone',
  'MailingStreet',
  'MailingCity',
  'MailingState',
  'MailingPostalCode',
  'MailingCountry'
];
const EDITABLE_TYPES = [
  'Text',
  'TextArea',
  'LongTextArea',
  'Email',
  'Phone',
  'Url',
  'Date',
  'DateTime',
  'Checkbox',
  'Number',
  'Percent',
  'Picklist',
  'MultiselectPicklist'
];
// Module key (BarnCRM_Module row) to the package folder that holds its objects.
const FOLDERS = {
  Volunteers: 'volunteers',
  Events: 'events',
  Giving: 'giving',
  CorporateHub: 'corporatehub'
};
const ACTION_CLASSES = {
  Volunteers: 'volunteers/main/default/classes/VolunteersPortalExtension.cls',
  Events: 'events/main/default/classes/EventsPortalExtension.cls',
  CorporateHub: 'corporatehub/main/default/classes/CorporateHubPortalExtension.cls'
};

function fieldFile(objectName, field) {
  for (const folder of fs.readdirSync(PACKAGES)) {
    const file = path.join(
      PACKAGES,
      folder,
      'main/default/objects',
      objectName,
      'fields',
      field + '.field-meta.xml'
    );
    if (fs.existsSync(file)) {
      return fs.readFileSync(file, 'utf8');
    }
  }
  return null;
}

function tag(xml, name) {
  const match = new RegExp('<' + name + '>([^<]*)</' + name + '>').exec(xml);
  return match ? match[1] : null;
}

function cases() {
  const out = [];
  [
    ['volunteer', volunteer],
    ['speaker', speaker],
    ['donor', donor],
    ['board', board]
  ].forEach(([name, template]) => {
    template.pages.forEach((page) => out.push([name + ' ' + page.key, template, page]));
  });
  return out;
}

describe('shipped portal templates', () => {
  it.each([
    ['volunteer', volunteer],
    ['speaker', speaker],
    ['donor', donor],
    ['board', board]
  ])('%s passes the shape rules and names its module', (name, template) => {
    expect(checkTemplate(template)).toEqual([]);
    expect(template.key).toBe(name);
    expect(template.requiresModules).toHaveLength(1);
    expect(FOLDERS[template.requiresModules[0]]).toBeDefined();
  });

  it.each(cases())(
    '%s: every field, test and order names a real field',
    (label, template, page) => {
      const objectName = page.kind === 'person' ? 'Contact' : page.object;
      const known = (field) => {
        if (BUILT_IN.includes(field)) {
          return true;
        }
        if (objectName === 'Contact' && CONTACT_STANDARD.includes(field)) {
          return true;
        }
        return fieldFile(objectName, field) !== null;
      };
      const names = page.fields.map((f) => f.field);
      (page.where || []).forEach((test) => names.push(test.field));
      if (page.orderBy) {
        names.push(page.orderBy.split(' ')[0]);
      }
      if (page.kind === 'related' && !page.personField.includes('.')) {
        names.push(page.personField);
      }
      names.forEach((field) => {
        if (field.includes('.')) {
          const [relation, parentField] = field.split('.');
          const link = fieldFile(objectName, relation.replace(/__r$/, '__c'));
          expect(link).not.toBeNull();
          const target = tag(link, 'referenceTo');
          expect(BUILT_IN.includes(parentField) || fieldFile(target, parentField) !== null).toBe(
            true
          );
        } else {
          expect([label, field, known(field)]).toEqual([label, field, true]);
        }
      });
    }
  );

  it.each(cases())('%s: only plain, writable, non-lookup fields are editable', (label, t, page) => {
    page.fields
      .filter((f) => f.edit)
      .forEach((f) => {
        // Name is the object's own text field; Contact's standard fields are Core's.
        if (f.field === 'Name' || (page.kind === 'person' && CONTACT_STANDARD.includes(f.field))) {
          return;
        }
        const xml = fieldFile(page.object || 'Contact', f.field);
        expect(xml).not.toBeNull();
        expect(tag(xml, 'formula')).toBeNull();
        expect(EDITABLE_TYPES).toContain(tag(xml, 'type'));
      });
  });

  it.each(cases())('%s: the person link is a Contact lookup, never editable', (label, t, page) => {
    if (page.kind !== 'related') {
      return;
    }
    expect(page.fields.filter((f) => f.edit && f.field === page.personField)).toEqual([]);
    const [first, second] = page.personField.split('.');
    const link = fieldFile(page.object, second ? first.replace(/__r$/, '__c') : first);
    expect(link).not.toBeNull();
    if (second) {
      expect(tag(fieldFile(tag(link, 'referenceTo'), second), 'referenceTo')).toBe('Contact');
      expect(page.fields.filter((f) => f.edit)).toEqual([]);
      expect((page.actions || []).filter((a) => typeof a === 'string')).toEqual([]);
    } else {
      expect(tag(link, 'referenceTo')).toBe('Contact');
    }
  });

  it('catalog pages are read only and carry fixed tests', () => {
    cases()
      .filter(([, , page]) => page.kind === 'catalog')
      .forEach(([, , page]) => {
        expect(page.fields.filter((f) => f.edit)).toEqual([]);
        expect(page.where.length).toBeGreaterThan(0);
        expect(page.actions.filter((a) => typeof a === 'string')).toEqual([]);
      });
  });

  it('the donor template takes no payments and changes only contact details', () => {
    const text = JSON.stringify(donor);
    expect(text).not.toMatch(/Payment|Card|create/);
    donor.pages.forEach((page) => {
      expect(page.actions.filter((a) => typeof a !== 'string' || a !== 'update')).toEqual([]);
      if (page.actions.length > 0) {
        expect(page.kind).toBe('person');
        expect(page.key).toBe('contact');
      }
    });
  });

  it('every module action a template names is offered by its module class', () => {
    [volunteer, speaker, board].forEach((template) => {
      const source = fs.readFileSync(
        path.join(PACKAGES, ACTION_CLASSES[template.requiresModules[0]]),
        'utf8'
      );
      template.pages
        .flatMap((page) => page.actions)
        .filter((a) => typeof a === 'object')
        .forEach((a) => expect(source).toContain("'" + a.extension + "'"));
    });
  });

  it('the board template never lets a member edit a vote, minutes or a status', () => {
    board.pages.forEach((page) => {
      page.fields
        .filter((f) => f.edit)
        .forEach((f) => expect(f.field).not.toMatch(/Vote__c|Minutes|Status__c|Attendance__c/));
    });
  });

  it('titles and labels are in title case', () => {
    const small = ['a', 'an', 'and', 'for', 'of', 'the', 'to'];
    const titleCase = (text) =>
      text
        .split(' ')
        .every((word, i) => (small.includes(word) && i > 0 ? true : /^[A-Z0-9]/.test(word)));
    cases().forEach(([, , page]) => {
      expect([page.title, titleCase(page.title)]).toEqual([page.title, true]);
      page.fields
        .filter((f) => f.label)
        .forEach((f) => expect([f.label, titleCase(f.label)]).toEqual([f.label, true]));
    });
  });
});
