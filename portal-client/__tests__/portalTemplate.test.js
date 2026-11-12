import { checkTemplate } from '../src/portalTemplate.js';
import sample from '../templates/sample.json';

function copy() {
  return JSON.parse(JSON.stringify(sample));
}

describe('checkTemplate', () => {
  it('passes the shipped sample template', () => {
    expect(checkTemplate(sample)).toEqual([]);
    expect(checkTemplate(JSON.stringify(sample))).toEqual([]);
  });

  it('refuses text that is not JSON, and the wrong version', () => {
    expect(checkTemplate('{ pages')).toEqual(['The template is not valid JSON']);
    const old = copy();
    old.schemaVersion = 2;
    expect(checkTemplate(old)).toEqual(['schemaVersion must be 1']);
  });

  it('refuses what Salesforce would refuse for its shape', () => {
    const t = copy();
    t.pages[1].fields.push({ field: 'Organization__r.Name', edit: true });
    t.pages[1].where[0].op = 'like';
    t.pages[0].actions = ['create'];
    t.pages.push({ key: 'list', kind: 'catalog', object: 'Shift__c', fields: [{ field: 'Name' }] });
    t.pages.push({ key: 'roles', kind: 'person', fields: [{ field: 'Email' }] });
    const problems = checkTemplate(t);
    expect(problems).toEqual(
      expect.arrayContaining([
        'Page roles: Organization__r.Name cannot be edited in a portal',
        'Page roles: where op like is not known',
        'Page profile: action create is not allowed here',
        'Page list: a catalog page needs at least one where test',
        'Two pages have the key roles'
      ])
    );
  });

  it('refuses the link to the person being editable and a bad order', () => {
    const t = copy();
    t.pages[1].fields.push({ field: 'Contact__c', edit: true });
    t.pages[1].orderBy = 'Role__c; DELETE';
    expect(checkTemplate(t)).toEqual([
      'Page roles: Contact__c cannot be edited in a portal',
      'Page roles: orderBy must be a field, then ASC or DESC'
    ]);
  });

  it('checks personScope, calendar, download and scan', () => {
    const scope = {
      field: 'Event_Registration__r.Event__c',
      object: 'Event_Attendee__c',
      personField: 'Contact__c',
      valueField: 'Event_Registration__r.Event__c',
      where: [{ field: 'Status__c', op: 'notEquals', value: 'Cancelled' }]
    };
    const good = copy();
    good.pages.push({
      key: 'people',
      kind: 'catalog',
      object: 'Event_Attendee__c',
      fields: [{ field: 'Badge_Name__c' }, { field: 'Starts__c' }],
      where: [{ field: 'Networking_Opt_In__c', op: 'equals', value: true }],
      personScope: scope,
      calendar: { title: 'Badge_Name__c', start: 'Starts__c' },
      download: true
    });
    good.pages[1].fields[1].scan = true;
    expect(checkTemplate(good)).toEqual([]);

    const bad = copy();
    bad.pages[1].personScope = scope;
    bad.pages[1].fields.push({ field: 'Status__c', scan: true });
    bad.pages[1].calendar = { title: 'Role__c', start: 'Nope__c' };
    bad.pages[1].download = 'yes';
    bad.pages.push({
      key: 'people',
      kind: 'catalog',
      object: 'Event_Attendee__c',
      fields: [{ field: 'Name' }],
      where: [{ field: 'Name', op: 'isNotBlank' }],
      personScope: { field: 'Event__c; DELETE', object: 'Event_Attendee__c', valueField: 'a.b.c' }
    });
    expect(checkTemplate(bad)).toEqual([
      'Page roles: Status__c can be scanned only as an edited text field',
      'Page roles: calendar start must be a field on the page',
      'Page roles: personScope is for catalog pages',
      'Page roles: download must be true or false',
      'Page people: personScope field must be a lookup or Id',
      'Page people: personScope personField must be a lookup to Contact',
      'Page people: personScope valueField must be a lookup to what field names'
    ]);
  });
});
