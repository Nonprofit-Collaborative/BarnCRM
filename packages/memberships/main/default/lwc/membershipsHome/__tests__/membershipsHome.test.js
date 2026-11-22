// The GraphQL and object info test wire adapters are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import MembershipsHome from 'c/membershipsHome';
import { graphql } from 'lightning/graphql';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import { expectAccessible } from 'barn/a11y';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);

const TERM_ID = 'a0M000000000001AAA';
const RENEWAL_ID = 'a0M000000000002AAA';

const infos = (termCreateable, levelCreateable) => ({
  results: [
    {
      statusCode: 200,
      result: {
        createable: termCreateable,
        fields: {
          Name: { label: 'Membership Number' },
          Member_Name__c: { label: 'Member Name' },
          Level__c: { label: 'Level' },
          End_Date__c: { label: 'End Date' },
          Start_Date__c: { label: 'Start Date' },
          Status__c: { label: 'Status' }
        }
      }
    },
    { statusCode: 200, result: { createable: levelCreateable, fields: {} } }
  ]
});

const field = (value, displayValue) => ({ value, displayValue });

function term(id, status, dateField, date) {
  return {
    node: {
      Id: id,
      Name: field('MEM-0001'),
      Member_Name__c: field('Harper Lee'),
      Level__r: { Name: field('Household') },
      Status__c: field(status, status),
      [dateField]: field(date)
    }
  };
}

function home({ terms = 3, levels = 1, expiring = true, renewals = true } = {}) {
  return {
    uiapi: {
      query: {
        terms: { totalCount: terms },
        levels: { totalCount: levels },
        active: { totalCount: 40 },
        grace: { totalCount: 3 },
        expiring: {
          totalCount: expiring ? 5 : 0,
          edges: expiring ? [term(TERM_ID, 'Current', 'End_Date__c', '2026-12-01')] : []
        },
        renewals: {
          totalCount: renewals ? 7 : 0,
          edges: renewals ? [term(RENEWAL_ID, 'Pending', 'Start_Date__c', '2026-11-15')] : []
        }
      }
    }
  };
}

function build() {
  const element = createElement('c-memberships-home', { is: MembershipsHome });
  document.body.appendChild(element);
  return element;
}

const flush = () => Promise.resolve().then(() => Promise.resolve());
const find = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-memberships-home', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the figures and the expiring and renewal lists', async () => {
    const element = build();
    getObjectInfos.emit(infos(true, true));
    graphql.emit(home());
    await flush();

    expect(find(element, '[data-id="shell"]').title).toBe('c.Memberships_Home_Title');
    expect(find(element, '[data-id="active"]').value).toBe(40);
    expect(find(element, '[data-id="expiring"]').value).toBe(5);
    expect(find(element, '[data-id="grace"]').value).toBe(3);
    expect(find(element, '[data-id="renewals"]').value).toBe(7);

    const expiring = find(element, 'section[data-id="expiring-list"]');
    const cells = expiring.querySelectorAll('td');
    expect(cells[1].textContent).toBe('Harper Lee');
    expect(cells[2].textContent).toBe('Household');
    expect(cells[3].textContent).not.toBe('');
    expect(expiring.querySelector('c-barn-status-badge').status).toBe('current');
    expect(expiring.querySelectorAll('th')[3].textContent).toBe('End Date');
    const renewals = find(element, 'section[data-id="renewals-list"]');
    expect(renewals.querySelectorAll('th')[3].textContent).toBe('Start Date');
    expect(renewals.querySelector('a').getAttribute('href')).toBe(`/${RENEWAL_ID}`);

    find(element, '[data-id="new-membership"]').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Membership_Term__c', actionName: 'new' }
    });
    await expectAccessible(element);
  });

  it('asks for today, 30 days ahead and 30 days back', async () => {
    build();
    await flush();
    const { today, soon, since } = graphql.getLastConfig().variables;
    expect(today).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    const ahead = (new Date(soon).getTime() - new Date(today).getTime()) / 86400000;
    expect(Math.round(ahead)).toBe(30);
    expect(Math.round((Date.now() - new Date(since).getTime()) / 86400000)).toBe(30);
  });

  it('points to a level first when there is none', async () => {
    const element = build();
    getObjectInfos.emit(infos(true, true));
    graphql.emit(home({ terms: 0, levels: 0, expiring: false, renewals: false }));
    await flush();

    const firstRun = find(element, '[data-id="first-run"]');
    expect(firstRun.heading).toBe('c.Memberships_Home_LevelFirstHeading');
    expect(find(element, '[data-id="first-run-member"]')).toBeNull();
    find(element, '[data-id="first-run-level"]').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Membership_Level__c', actionName: 'new' }
    });
    await expectAccessible(element);
  });

  it('points to the first membership once a level exists', async () => {
    const element = build();
    getObjectInfos.emit(infos(true, false));
    graphql.emit(home({ terms: 0, expiring: false, renewals: false }));
    await flush();

    expect(find(element, '[data-id="first-run"]').heading).toBe(
      'c.Memberships_Home_MemberFirstHeading'
    );
    expect(find(element, '[data-id="first-run-member"]')).not.toBeNull();
    expect(find(element, '[data-id="first-run-level"]')).toBeNull();
  });

  it('shows next steps for empty lists and hides New Membership from a reader', async () => {
    const element = build();
    getObjectInfos.emit(infos(false, false));
    graphql.emit(home({ expiring: false, renewals: false }));
    await flush();

    const empties = element.shadowRoot.querySelectorAll('[data-id="section-empty"]');
    expect(empties).toHaveLength(2);
    expect(empties[0].message).toBe('c.Memberships_Home_NoExpiringNext');
    expect(find(element, '[data-id="new-membership"]')).toBeNull();
  });

  it('says so when the read fails', async () => {
    const element = build();
    graphql.emitErrors([{ message: 'No access' }]);
    await flush();

    expect(find(element, '[data-id="error-message"]').message).toBe(
      'c.Memberships_Home_LoadFailed'
    );
    expect(find(element, '[data-id="tiles"]')).toBeNull();
  });
});
