// The GraphQL and object info test wire adapters are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import FormsHome from 'c/formsHome';
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

const FORM_ID = 'a0F000000000001AAA';
const SUBMISSION_ID = 'a0G000000000001AAA';

const infos = (createable) => ({
  results: [
    {
      statusCode: 200,
      result: {
        createable,
        fields: {
          Name: { label: 'Form Name' },
          Status__c: { label: 'Status' },
          LastModifiedDate: { label: 'Last Modified Date' }
        }
      }
    },
    {
      statusCode: 200,
      result: {
        createable: false,
        fields: { Name: { label: 'Submission Number' }, Form_Name__c: { label: 'Form Name' } }
      }
    }
  ]
});

const field = (value, displayValue) => ({ value, displayValue });

function home({ forms = 1, submissions = true } = {}) {
  return {
    uiapi: {
      query: {
        forms: {
          totalCount: forms,
          edges: forms
            ? [
                {
                  node: {
                    Id: FORM_ID,
                    Name: field('Volunteer Sign-Up'),
                    Status__c: field('Published', 'Published'),
                    LastModifiedDate: field('2026-11-20T10:00:00.000Z')
                  }
                }
              ]
            : []
        },
        published: { totalCount: 4 },
        submissions: {
          edges: submissions
            ? [
                {
                  node: {
                    Id: SUBMISSION_ID,
                    Name: field('SUB-000001'),
                    Form_Name__c: field('Volunteer Sign-Up'),
                    Status__c: field('Needs Review', 'Needs Review'),
                    CreatedDate: field('2026-11-21T09:00:00.000Z')
                  }
                }
              ]
            : []
        },
        received: { totalCount: 12 },
        review: { totalCount: 2 }
      }
    }
  };
}

function build() {
  const element = createElement('c-forms-home', { is: FormsHome });
  document.body.appendChild(element);
  return element;
}

const flush = () => Promise.resolve().then(() => Promise.resolve());
const find = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-forms-home', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the figures and both lists, with New Form for a creator', async () => {
    const element = build();
    getObjectInfos.emit(infos(true));
    graphql.emit(home());
    await flush();

    const shell = find(element, '[data-id="shell"]');
    expect(shell.title).toBe('c.Forms_Home_Title');
    expect(find(element, '[data-id="published"]').value).toBe(4);
    expect(find(element, '[data-id="received"]').value).toBe(12);
    expect(find(element, '[data-id="review"]').value).toBe(2);
    expect(find(element, '[data-id="published"]').href).toBe('/lightning/o/Form__c/list');

    const forms = find(element, 'section[data-id="forms"]');
    expect(forms.querySelectorAll('tr[data-id="row"]')).toHaveLength(1);
    expect(forms.querySelector('a').getAttribute('href')).toBe(`/${FORM_ID}`);
    expect(forms.querySelector('th').textContent).toBe('Form Name');
    const badge = find(element, 'section[data-id="submissions"] c-barn-status-badge');
    expect(badge.status).toBe('review');
    expect(badge.label).toBe('Needs Review');
    expect(find(element, '[data-id="first-run"]')).toBeNull();

    find(element, '[data-id="new-form"]').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Form__c', actionName: 'new' }
    });
    await expectAccessible(element);
  });

  it('asks for a date filter from 30 days back', async () => {
    build();
    await flush();
    const since = new Date(graphql.getLastConfig().variables.since).getTime();
    const days = (Date.now() - since) / 86400000;
    expect(Math.round(days)).toBe(30);
  });

  it('offers the first form before there is one, and hides New Form from a reader', async () => {
    const element = build();
    getObjectInfos.emit(infos(false));
    graphql.emit(home({ forms: 0, submissions: false }));
    await flush();

    expect(find(element, '[data-id="first-run"]')).not.toBeNull();
    expect(find(element, '[data-id="first-run-new"]')).toBeNull();
    expect(find(element, '[data-id="new-form"]')).toBeNull();
    expect(find(element, '[data-id="tiles"]')).toBeNull();
    await expectAccessible(element);
  });

  it('shows the next step when no submission has come in', async () => {
    const element = build();
    getObjectInfos.emit(infos(true));
    graphql.emit(home({ submissions: false }));
    await flush();

    const empty = find(element, 'section[data-id="submissions"] [data-id="section-empty"]');
    expect(empty.heading).toBe('c.Forms_Home_NoSubmissions');
    expect(empty.message).toBe('c.Forms_Home_NoSubmissionsNext');
  });

  it('says so when the read fails', async () => {
    const element = build();
    graphql.emitErrors([{ message: 'No access' }]);
    await flush();

    expect(find(element, '[data-id="error-message"]').message).toBe('c.Forms_Home_LoadFailed');
    expect(find(element, 'lightning-spinner')).toBeNull();
    expect(find(element, '[data-id="tiles"]')).toBeNull();
  });
});
