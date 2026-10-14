import { createElement } from 'lwc';
import ImportRowRules from 'c/importRowRules';

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function render(skipRows = [], uniqueBy = []) {
  const element = createElement('c-import-row-rules', { is: ImportRowRules });
  Object.assign(element, { columnNames: ['Status', 'Email', 'Event'], skipRows, uniqueBy });
  document.body.appendChild(element);
  return element;
}

function rules(element) {
  return element.shadowRoot.querySelectorAll('[data-id="rule"]');
}

function field(element, name, index = 0) {
  return rules(element)[index].querySelector(`[data-name="${name}"]`);
}

describe('the rows to load', () => {
  let changes;

  beforeEach(() => {
    changes = [];
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function listen(element) {
    element.addEventListener('change', (event) => changes.push(event.detail));
  }

  it('shows the saved rules and key columns', async () => {
    const element = render([{ column: 'Status', test: 'equals', text: 'Cancelled' }], ['Email']);
    await flush();
    expect(rules(element)).toHaveLength(1);
    expect(field(element, 'column').value).toBe('Status');
    expect(field(element, 'text').value).toBe('Cancelled');
    const keys = element.shadowRoot.querySelector('[data-id="unique-by"]');
    expect(keys.value).toEqual(['Email']);
    expect(keys.options.map((option) => option.value)).toEqual(['Status', 'Email', 'Event']);
  });

  it('adds a rule, edits it, and sends only what each test reads', async () => {
    const element = render();
    listen(element);
    await flush();
    element.shadowRoot.querySelector('[data-id="add-rule"]').click();
    await flush();
    field(element, 'text').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'cancelled' } })
    );
    await flush();
    expect(changes[changes.length - 1].skipRows).toEqual([
      { column: 'Status', test: 'equals', text: 'cancelled' }
    ]);
    field(element, 'test').dispatchEvent(new CustomEvent('change', { detail: { value: 'blank' } }));
    await flush();
    expect(field(element, 'text')).toBeNull();
    expect(changes[changes.length - 1].skipRows).toEqual([{ column: 'Status', test: 'blank' }]);
    element.shadowRoot
      .querySelector('[data-id="unique-by"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: ['Event', 'Email'] } }));
    expect(changes[changes.length - 1].uniqueBy).toEqual(['Event', 'Email']);
    element.shadowRoot.querySelector('[data-id="remove-rule"]').click();
    await flush();
    expect(rules(element)).toHaveLength(0);
    expect(changes[changes.length - 1].skipRows).toEqual([]);
  });

  it('allows no more than five rules', async () => {
    const five = Array.from({ length: 5 }, () => ({ column: 'Status', test: 'blank' }));
    const element = render(five);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="add-rule"]').disabled).toBe(true);
  });
});
