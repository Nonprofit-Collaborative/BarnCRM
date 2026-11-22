// The GraphQL and object info test wire adapters are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import PortalBuilderHome from 'c/portalBuilderHome';
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

const PORTAL_ID = 'a0P000000000001AAA';
const ACCESS_ID = 'a0Q000000000001AAA';

const infos = (createable) => ({
  results: [
    {
      statusCode: 200,
      result: {
        createable,
        fields: {
          Name: { label: 'Portal Name' },
          Status__c: { label: 'Status' },
          Access_Mode__c: { label: 'Access Mode' }
        }
      }
    },
    {
      statusCode: 200,
      result: {
        createable: false,
        fields: {
          Person__c: { label: 'Person' },
          Portal__c: { label: 'Portal' },
          Last_Sign_In__c: { label: 'Last Sign-In' }
        }
      }
    }
  ]
});

const field = (value, displayValue) => ({ value, displayValue });

function home({ portals = 1, signIns = true, person = true } = {}) {
  return {
    uiapi: {
      query: {
        portals: {
          totalCount: portals,
          edges: portals
            ? [
                {
                  node: {
                    Id: PORTAL_ID,
                    Name: field('Member Portal'),
                    Status__c: field('Active', 'Active'),
                    Access_Mode__c: field('Invited', 'Invited')
                  }
                }
              ]
            : []
        },
        live: { totalCount: 1 },
        access: { totalCount: 25 },
        suspended: { totalCount: 2 },
        signIns: {
          totalCount: signIns ? 9 : 0,
          edges: signIns
            ? [
                {
                  node: {
                    Id: ACCESS_ID,
                    Name: field('PA-000001'),
                    Person__r: person ? { Name: field('Harper Lee') } : null,
                    Portal__r: { Name: field('Member Portal') },
                    Last_Sign_In__c: field('2026-11-20T15:30:00.000Z')
                  }
                }
              ]
            : []
        }
      }
    }
  };
}

function build() {
  const element = createElement('c-portal-builder-home', { is: PortalBuilderHome });
  document.body.appendChild(element);
  return element;
}

const flush = () => Promise.resolve().then(() => Promise.resolve());
const find = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-portal-builder-home', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the figures, the portals and the latest sign-ins', async () => {
    const element = build();
    getObjectInfos.emit(infos(true));
    graphql.emit(home());
    await flush();

    expect(find(element, '[data-id="shell"]').title).toBe('c.Portal_Home_Title');
    expect(find(element, '[data-id="live"]').value).toBe(1);
    expect(find(element, '[data-id="access"]').value).toBe(25);
    expect(find(element, '[data-id="suspended"]').value).toBe(2);
    expect(find(element, '[data-id="sign-ins"]').value).toBe(9);
    expect(find(element, '[data-id="access"]').href).toBe('/lightning/o/Portal_Access__c/list');

    const portals = find(element, 'section[data-id="portals"]');
    expect(portals.querySelector('c-barn-status-badge').status).toBe('active');
    expect(portals.querySelectorAll('td')[2].textContent).toBe('Invited');
    const signIns = find(element, 'section[data-id="sign-in-list"]');
    expect(signIns.querySelector('a').textContent).toBe('Harper Lee');
    expect(signIns.querySelector('a').getAttribute('href')).toBe(`/${ACCESS_ID}`);
    expect(signIns.querySelectorAll('th')[2].textContent).toBe('Last Sign-In');

    find(element, '[data-id="new-portal"]').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Portal__c', actionName: 'new' }
    });
    await expectAccessible(element);
  });

  it('names a sign-in by its access record when the person cannot be read', async () => {
    const element = build();
    getObjectInfos.emit(infos(true));
    graphql.emit(home({ person: false }));
    await flush();

    expect(find(element, 'section[data-id="sign-in-list"] a').textContent).toBe('PA-000001');
  });

  it('offers the first portal before there is one', async () => {
    const element = build();
    getObjectInfos.emit(infos(true));
    graphql.emit(home({ portals: 0, signIns: false }));
    await flush();

    expect(find(element, '[data-id="first-run"]')).not.toBeNull();
    find(element, '[data-id="first-run-new"]').click();
    expect(mockNavigate).toHaveBeenCalled();
    expect(find(element, '[data-id="tiles"]')).toBeNull();
    await expectAccessible(element);
  });

  it('shows the next step when nobody signed in, and no New Portal for a reader', async () => {
    const element = build();
    getObjectInfos.emit(infos(false));
    graphql.emit(home({ signIns: false }));
    await flush();

    const empty = find(element, 'section[data-id="sign-in-list"] [data-id="section-empty"]');
    expect(empty.message).toBe('c.Portal_Home_NoSignInsNext');
    expect(find(element, '[data-id="new-portal"]')).toBeNull();
  });

  it('says so when the read fails', async () => {
    const element = build();
    graphql.emitErrors([{ message: 'No access' }]);
    await flush();

    expect(find(element, '[data-id="error-message"]').message).toBe('c.Portal_Home_LoadFailed');
  });
});
