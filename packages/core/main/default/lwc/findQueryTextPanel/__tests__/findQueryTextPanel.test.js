import { createElement } from 'lwc';
import FindQueryTextPanel from 'c/findQueryTextPanel';

jest.mock(
  '@salesforce/label/c.Core_Find_TextMixed',
  () => ({ default: 'Add brackets where AND and OR are mixed.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_Find_TextSyntax',
  () => ({ default: 'Find could not read the query near: {0}' }),
  { virtual: true }
);

function mount(soql) {
  const element = createElement('c-find-query-text-panel', { is: FindQueryTextPanel });
  element.soql = soql;
  document.body.appendChild(element);
  return element;
}

const flush = () => Promise.resolve();

async function typeAndUse(element, text) {
  const area = element.shadowRoot.querySelector('[data-id="text"]');
  area.value = text;
  area.dispatchEvent(new CustomEvent('change'));
  await flush();
  element.shadowRoot.querySelector('[data-id="use"]').click();
  await flush();
}

describe('c-find-query-text-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('opens with the SOQL Find shows, and says it is open', async () => {
    const element = mount('SELECT Id, Name FROM Account LIMIT 200');
    const toggle = element.shadowRoot.querySelector('[data-id="toggle"]');
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    toggle.click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="text"]').value).toBe(
      'SELECT Id, Name FROM Account LIMIT 200'
    );
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
  });

  it('hands the parsed document to Find and closes', async () => {
    const element = mount('');
    const applied = jest.fn();
    element.addEventListener('apply', applied);
    element.shadowRoot.querySelector('[data-id="toggle"]').click();
    await flush();

    await typeAndUse(element, "SELECT Name FROM Contact WHERE LastName = 'Ruiz'");

    expect(applied).toHaveBeenCalledTimes(1);
    expect(applied.mock.calls[0][0].detail.document).toEqual({
      version: 1,
      object: 'Contact',
      fields: ['Name'],
      filter: {
        version: 1,
        conditions: [{ id: 1, field: 'LastName', operator: 'equals', value: 'Ruiz' }]
      }
    });
    expect(element.shadowRoot.querySelector('[data-id="text"]')).toBeNull();
  });

  it('says what is wrong and sends nothing', async () => {
    const element = mount('');
    const applied = jest.fn();
    element.addEventListener('apply', applied);
    element.shadowRoot.querySelector('[data-id="toggle"]').click();
    await flush();

    await typeAndUse(element, 'SELECT Name FROM Account WHERE A__c = 1 AND B__c = 2 OR C__c = 3');
    expect(element.shadowRoot.querySelector('[data-id="text-error"]').textContent).toContain(
      'Add brackets'
    );

    await typeAndUse(element, 'SELECT Name FROM Account WHERE');
    const error = element.shadowRoot.querySelector('[data-id="text-error"]');
    expect(error.textContent).toContain('Find could not read the query near:');
    expect(error.getAttribute('role')).toBe('alert');
    expect(applied).not.toHaveBeenCalled();
  });
});
