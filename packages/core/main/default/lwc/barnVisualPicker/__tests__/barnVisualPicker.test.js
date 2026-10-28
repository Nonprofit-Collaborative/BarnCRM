import { createElement } from 'lwc';
import BarnVisualPicker from 'c/barnVisualPicker';

// Storybook-style: nothing chosen, one chosen, a warning choice, and a change.
const OPTIONS = [
  {
    value: 'people',
    label: 'People and Organizations',
    description: 'People, households and organizations.',
    iconName: 'standard:household'
  },
  {
    value: 'gifts',
    label: 'Gifts',
    description: 'Gifts and who gave them.',
    iconName: 'standard:currency'
  },
  {
    value: 'delete',
    label: 'Delete the Records a File Lists',
    description: 'Sends listed records to the Recycle Bin.',
    iconName: 'utility:delete',
    warning: true
  }
];

function render(props) {
  const element = createElement('c-barn-visual-picker', { is: BarnVisualPicker });
  Object.assign(element, { label: 'What Are You Importing?', options: OPTIONS }, props);
  document.body.appendChild(element);
  return element;
}

const all = (element, id) => Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));

describe('c-barn-visual-picker', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: nothing chosen is one radio group under a legend', () => {
    const element = render();

    expect(element.shadowRoot.querySelector('fieldset legend').textContent).toBe(
      'What Are You Importing?'
    );
    const radios = all(element, 'choice');
    expect(radios).toHaveLength(3);
    expect(radios.every((radio) => radio.type === 'radio')).toBe(true);
    expect(new Set(radios.map((radio) => radio.name)).size).toBe(1);
    expect(radios.some((radio) => radio.checked)).toBe(false);
    expect(all(element, 'name').map((node) => node.textContent)).toEqual([
      'People and Organizations',
      'Gifts',
      'Delete the Records a File Lists'
    ]);
    // Each card's line is read as the description of its radio.
    const line = all(element, 'line')[1];
    expect(radios[1].getAttribute('aria-describedby')).toBe(line.getAttribute('id'));
    // The label belongs to its own radio.
    expect(all(element, 'card')[1].getAttribute('for')).toBe(radios[1].getAttribute('id'));
  });

  it('story: the chosen value is checked', () => {
    const element = render({ value: 'gifts' });
    expect(all(element, 'choice').map((radio) => radio.checked)).toEqual([false, true, false]);
  });

  it('story: a warning choice colors its icon', () => {
    const element = render();
    expect(all(element, 'icon').map((icon) => icon.variant)).toEqual([
      undefined,
      undefined,
      'warning'
    ]);
  });

  it('fires change with the chosen value', () => {
    const element = render();
    const handler = jest.fn();
    element.addEventListener('change', handler);

    all(element, 'choice')[2].click();

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({ value: 'delete' });
  });
});
