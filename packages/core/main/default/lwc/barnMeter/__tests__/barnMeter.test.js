import { createElement } from 'lwc';
import BarnMeter from 'c/barnMeter';

// Storybook-style: a percent, a part of a whole with its own text, and the edge cases.
function render(props) {
  const element = createElement('c-barn-meter', { is: BarnMeter });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-barn-meter', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: a percent shows the bar and the percent beside it', () => {
    const element = render({ label: 'Data Storage', value: 62 });
    expect(one(element, 'label').textContent).toBe('Data Storage');
    expect(one(element, 'bar').value).toBe(62);
    const formatted = one(element, 'value').querySelector('lightning-formatted-number');
    expect(formatted.value).toBeCloseTo(0.62);
    expect(formatted.formatStyle).toBe('percent');
  });

  it('story: part of a whole with its own text', () => {
    const element = render({ label: 'Steps Done', value: 3, max: 5, valueText: '3 of 5' });
    expect(one(element, 'bar').value).toBe(60);
    expect(one(element, 'value').textContent).toBe('3 of 5');
  });

  it.each([
    [7, 0, 0],
    [-2, 10, 0],
    [15, 10, 100],
    [undefined, 10, 0]
  ])('story: value %s of %s draws %s', (value, max, percent) => {
    const element = render({ label: 'Share', value, max });
    expect(one(element, 'bar').value).toBe(percent);
  });
});
