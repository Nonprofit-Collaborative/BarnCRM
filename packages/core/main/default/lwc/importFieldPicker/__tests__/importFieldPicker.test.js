import { createElement } from 'lwc';
import ImportFieldPicker from 'c/importFieldPicker';

const OPTIONS = [
  { label: 'Do not load', value: 'Ignore' },
  { label: 'Person: First Name', value: 'Contact1.FirstName' },
  { label: 'Person: Last Name', value: 'Contact1.LastName' },
  { label: 'Second person: Email', value: 'Contact2.Email' },
  { label: 'Organization: Name', value: 'Organization.Name' }
];

function render(properties = {}) {
  const element = createElement('c-import-field-picker', { is: ImportFieldPicker });
  Object.assign(
    element,
    { label: 'Target', options: OPTIONS, value: 'Ignore', pinnedValue: 'Ignore' },
    properties
  );
  document.body.appendChild(element);
  return element;
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

const input = (element) => element.shadowRoot.querySelector('[data-id="input"]');
const optionValues = (element) =>
  Array.from(element.shadowRoot.querySelectorAll('[data-id="option"]')).map(
    (option) => option.dataset.value
  );

async function type(element, text) {
  const box = input(element);
  box.value = text;
  box.dispatchEvent(new CustomEvent('input'));
  await flush();
}

describe('the type-to-search field picker', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the chosen field when closed and the whole list when opened', async () => {
    const element = render({ value: 'Contact1.LastName' });
    await flush();
    expect(input(element).value).toBe('Person: Last Name');
    expect(input(element).getAttribute('aria-expanded')).toBe('false');
    input(element).dispatchEvent(new CustomEvent('focus'));
    await flush();
    expect(input(element).getAttribute('aria-expanded')).toBe('true');
    expect(optionValues(element)).toEqual([
      'Ignore',
      'Contact1.FirstName',
      'Contact1.LastName',
      'Contact2.Email',
      'Organization.Name'
    ]);
  });

  it('groups people fields under their headings and pins Do not load first', async () => {
    const element = render();
    input(element).dispatchEvent(new CustomEvent('focus'));
    await flush();
    const headings = Array.from(element.shadowRoot.querySelectorAll('[data-id="group"]')).map(
      (heading) => heading.textContent.trim()
    );
    expect(headings).toEqual(['Person', 'Second person', 'Organization']);
    expect(optionValues(element)[0]).toBe('Ignore');
  });

  it('filters as the person types and keeps Do not load', async () => {
    const element = render();
    input(element).dispatchEvent(new CustomEvent('focus'));
    await type(element, 'email');
    expect(optionValues(element)).toEqual(['Ignore', 'Contact2.Email']);
    expect(element.shadowRoot.querySelector('[data-id="count"]').textContent).toContain(
      'Core_Import_FieldPickerCount'
    );
    await type(element, 'zzz');
    expect(optionValues(element)).toEqual(['Ignore']);
    expect(element.shadowRoot.querySelector('[data-id="none"]')).not.toBeNull();
  });

  it('marks a field another column already loads into', async () => {
    const element = render({ usedValues: ['Contact1.FirstName'] });
    input(element).dispatchEvent(new CustomEvent('focus'));
    await flush();
    const used = element.shadowRoot.querySelectorAll('[data-id="used"]');
    expect(used).toHaveLength(1);
    expect(used[0].closest('[data-id="option"]').dataset.value).toBe('Contact1.FirstName');
  });

  it('fires change with the chosen value and closes', async () => {
    const element = render();
    const handler = jest.fn();
    element.addEventListener('change', handler);
    input(element).dispatchEvent(new CustomEvent('focus'));
    await flush();
    element.shadowRoot.querySelector('[data-value="Contact2.Email"]').click();
    await flush();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({ value: 'Contact2.Email' });
    expect(input(element).getAttribute('aria-expanded')).toBe('false');
  });

  it('chooses the only match with Enter', async () => {
    const element = render();
    const handler = jest.fn();
    element.addEventListener('change', handler);
    input(element).dispatchEvent(new CustomEvent('focus'));
    await type(element, 'organization');
    input(element).dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    await flush();
    expect(handler.mock.calls[0][0].detail).toEqual({ value: 'Organization.Name' });
  });

  it('moves along the list with the arrow keys and chooses with Enter', async () => {
    const element = render();
    const handler = jest.fn();
    element.addEventListener('change', handler);
    input(element).dispatchEvent(new CustomEvent('focus'));
    await flush();
    input(element).dispatchEvent(
      new KeyboardEvent('keydown', { key: 'ArrowDown', cancelable: true })
    );
    await flush();
    const options = Array.from(element.shadowRoot.querySelectorAll('[data-id="option"]'));
    expect(element.shadowRoot.activeElement).toBe(options[0]);
    options[0].dispatchEvent(
      new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true })
    );
    expect(element.shadowRoot.activeElement).toBe(options[1]);
    options[1].dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true })
    );
    await flush();
    expect(handler.mock.calls[0][0].detail).toEqual({ value: 'Contact1.FirstName' });
  });

  it('closes with Escape without changing the value', async () => {
    const element = render();
    const handler = jest.fn();
    element.addEventListener('change', handler);
    input(element).dispatchEvent(new CustomEvent('focus'));
    await flush();
    input(element).dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', cancelable: true }));
    await flush();
    expect(input(element).getAttribute('aria-expanded')).toBe('false');
    expect(handler).not.toHaveBeenCalled();
  });
});
