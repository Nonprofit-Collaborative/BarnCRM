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
});
