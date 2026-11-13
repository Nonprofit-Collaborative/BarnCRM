/* The shipped templates (PB-03 to PB-08, EV-22, EV-28) checked offline against the package metadata
 * in this repository: Salesforce re-checks every call against the org, so a template that fails
 * here would be refused there. Also the person-scoped rules the templates must keep. */
import fs from 'fs';
import path from 'path';
import { checkTemplate } from '../src/portalTemplate.js';
import volunteer from '../templates/volunteer.json';
import speaker from '../templates/speaker.json';
import donor from '../templates/donor.json';
import board from '../templates/board.json';
import applicant from '../templates/applicant.json';
import member from '../templates/member.json';
import attendee from '../templates/attendee.json';
import sponsor from '../templates/sponsor.json';
import service from '../templates/service.json';
import partner from '../templates/partner.json';
import partnerFunders from '../templates/partner-funders.json';
import requests from '../templates/requests.json';

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
  CorporateHub: 'corporatehub',
  Scholarships: 'scholarships',
  Memberships: 'memberships',
  Programs: 'programs',
  Funders: 'funders',
  Projects: 'projects'
};
const ACTION_CLASSES = {
  Volunteers: 'volunteers/main/default/classes/VolunteersPortalExtension.cls',
  // Events hands the attendee app's actions to EventAttendeeApp, which names them.
  Events: [
    'events/main/default/classes/EventsPortalExtension.cls',
    'events/main/default/classes/EventAttendeeApp.cls'
  ],
  CorporateHub: 'corporatehub/main/default/classes/CorporateHubPortalExtension.cls',
  Scholarships: 'scholarships/main/default/classes/ScholarshipsPortalExtension.cls',
  Memberships: 'memberships/main/default/classes/MembershipsPortalExtension.cls',
  Giving: 'giving/main/default/classes/GivingPortalPayments.cls'
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
    ['board', board],
    ['applicant', applicant],
    ['member', member],
    ['attendee', attendee],
    ['sponsor', sponsor],
    ['service', service],
    ['partner', partner],
    ['partner-funders', partnerFunders],
    ['requests', requests]
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
    ['board', board],
    ['applicant', applicant],
    ['member', member],
    ['attendee', attendee],
    ['sponsor', sponsor],
    ['service', service],
    ['partner', partner],
    ['partner-funders', partnerFunders],
    ['requests', requests]
  ])('%s passes the shape rules and names its module', (name, template) => {
    expect(checkTemplate(template)).toEqual([]);
    expect(template.key).toBe(name);
    expect(template.requiresModules.length).toBeGreaterThan(0);
    template.requiresModules.forEach((module) => expect(FOLDERS[module]).toBeDefined());
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
      Object.values(page.calendar || {}).forEach((field) =>
        expect(page.fields.map((f) => f.field)).toContain(field)
      );
      names.forEach((field) => {
        if (field.includes('.')) {
          const [relation, parentField] = field.split('.');
          const link = fieldFile(objectName, relation.replace(/__r$/, '__c'));
          expect(link).not.toBeNull();
          const target = tag(link, 'referenceTo');
          const standard = target === 'Contact' && CONTACT_STANDARD.includes(parentField);
          expect([
            field,
            BUILT_IN.includes(parentField) || standard || fieldFile(target, parentField) !== null
          ]).toEqual([field, true]);
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

  it('the donor template edits only contact details and pays only through Pay Online and Update Card on pledges', () => {
    // No card field and no create: the card is only ever typed on the processor's page.
    const text = JSON.stringify(donor).replace('"Giving.UpdateCard","label":"Update Card"', '');
    expect(text).not.toMatch(/Card|create/);
    donor.pages.forEach((page) => {
      const updates = page.actions.filter((a) => a === 'update');
      const modules = page.actions.filter((a) => typeof a === 'object');
      expect(page.actions.length).toBe(updates.length + modules.length);
      if (updates.length > 0) {
        expect(page.kind).toBe('person');
        expect(page.key).toBe('contact');
      }
      // PAY-03 (ADR-0210) and PAY-04 (ADR-0218 payments subscriptions): the two module
      // actions, on pledges only.
      modules.forEach((action) => {
        expect(['Giving.PayOnline', 'Giving.UpdateCard']).toContain(action.extension);
        expect(page.key).toBe('pledges');
      });
    });
  });

  it('every module action a template names is offered by its module class', () => {
    [volunteer, speaker, board, applicant, member, donor, attendee, sponsor].forEach((template) => {
      const source = []
        .concat(ACTION_CLASSES[template.requiresModules[0]])
        .map((file) => fs.readFileSync(path.join(PACKAGES, file), 'utf8'))
        .join('\n');
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

  it('the member directory lists only members who opted in, and edits nothing', () => {
    const directory = member.pages.find((page) => page.key === 'directory');
    expect(directory.kind).toBe('catalog');
    expect(directory.search).toBe(true);
    expect(directory.where).toContainEqual({
      field: 'Directory_Opt_In__c',
      op: 'equals',
      value: 'true'
    });
    expect(directory.fields.map((f) => f.field)).not.toContain('Contact__c');
  });

  it('the requests template shows only shared updates and never edits status or resolution', () => {
    const [mine, updates] = requests.pages;
    mine.fields
      .filter((f) => f.edit)
      .forEach((f) => expect(f.field).not.toMatch(/Status__c|Resolution__c|Due_Date__c|Owner/));
    expect(updates.actions).toEqual([]);
    expect(updates.where).toContainEqual({ field: 'Shared__c', op: 'equals', value: 'true' });
  });

  it('titles and labels are in title case', () => {
    const small = ['a', 'an', 'and', 'for', 'in', 'of', 'the', 'to'];
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

  it.each(cases().filter(([, , page]) => page.personScope))(
    '%s: the person scope names real lookups to the same object',
    (label, template, page) => {
      const scope = page.personScope;
      // A path's lookup (one hop allowed) and the object it points to.
      const lookupOf = (objectName, fieldPath) => {
        if (fieldPath === 'Id') {
          return objectName;
        }
        const parts = fieldPath.split('.');
        let xml = fieldFile(objectName, parts[0].replace(/__r$/, '__c'));
        if (parts.length === 2) {
          xml = fieldFile(tag(xml, 'referenceTo'), parts[1]);
        }
        expect([label, fieldPath, xml !== null]).toEqual([label, fieldPath, true]);
        return tag(xml, 'referenceTo');
      };
      expect(lookupOf(scope.object, scope.valueField)).toBe(lookupOf(page.object, scope.field));
      expect(lookupOf(scope.object, scope.personField)).toBe('Contact');
      (scope.where || []).forEach((test) =>
        expect(fieldFile(scope.object, test.field)).not.toBeNull()
      );
    }
  );

  it('the attendee app lists only opted-in attendees, without email, phone or address', () => {
    const list = attendee.pages.find((page) => page.key === 'attendees');
    expect(list.where).toContainEqual({
      field: 'Networking_Opt_In__c',
      op: 'equals',
      value: 'true'
    });
    const fields = list.fields.map((f) => f.field).join(' ');
    expect(fields).not.toMatch(/Email|Phone|Address|Contact|Networking_Contact__c/);
    attendee.pages
      .filter((page) => page.kind === 'catalog')
      .forEach((page) => expect(page.personScope).toBeDefined());
  });

  it('sponsors scan badge codes, and partners never see referral notes', () => {
    const leads = sponsor.pages.find((page) => page.key === 'leads');
    expect(leads.fields.find((f) => f.field === 'Badge_Code__c').scan).toBe(true);
    expect(leads.personField).toBe('Scanned_By__c');
    [partner, partnerFunders, service].forEach((template) =>
      expect(JSON.stringify(template)).not.toMatch(/Notes__c|Case_Note__c/)
    );
    const shared = partner.pages.find((page) => page.key === 'referrals');
    expect(shared.where).toContainEqual({
      field: 'Shared_With_Partner__c',
      op: 'equals',
      value: 'true'
    });
    expect(partnerFunders.pages.slice(0, 1)).toEqual(partner.pages.slice(0, 1));
  });
});
