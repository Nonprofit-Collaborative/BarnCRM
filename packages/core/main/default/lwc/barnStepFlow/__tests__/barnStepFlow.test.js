import { createElement } from 'lwc';
import BarnStepFlow from 'c/barnStepFlow';

jest.mock('@salesforce/label/c.Core_Kit_StepOf', () => ({ default: 'Step {0} of {1}: {2}' }), {
  virtual: true
});

// Storybook-style: first step without Back, a middle step with Back, and an unknown step.
const STEPS = [
  { value: '1', label: 'Choose File Type' },
  { value: '2', label: 'Upload File' },
  { value: '3', label: 'Check Columns' }
];

function render(props) {
  const element = createElement('c-barn-step-flow', { is: BarnStepFlow });
  Object.assign(element, { steps: STEPS }, props);
  document.body.appendChild(element);
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-barn-step-flow', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('story: the first step shows the path and no Back', () => {
    const element = render({ currentStep: '1' });

    const path = one(element, 'path');
    expect(path.type).toBe('path');
    expect(path.currentStep).toBe('1');
    const steps = Array.from(element.shadowRoot.querySelectorAll('lightning-progress-step'));
    expect(steps.map((step) => [step.value, step.label])).toEqual([
      ['1', 'Choose File Type'],
      ['2', 'Upload File'],
      ['3', 'Check Columns']
    ]);
    expect(one(element, 'heading').textContent).toBe('Step 1 of 3: Choose File Type');
    expect(one(element, 'heading').tagName).toBe('H2');
    expect(one(element, 'back')).toBeNull();
    expect(element.shadowRoot.querySelector('slot[name="actions"]')).not.toBeNull();
  });

  it('story: a middle step with Back fires back', () => {
    const element = render({ currentStep: '2', canGoBack: true });
    const handler = jest.fn();
    element.addEventListener('back', handler);

    expect(one(element, 'heading').textContent).toBe('Step 2 of 3: Upload File');
    const back = one(element, 'back');
    expect(back.label).toBe('c.Core_Kit_Back');
    back.click();
    expect(handler).toHaveBeenCalledTimes(1);
  });

  it('story: an unknown step leaves the heading empty', () => {
    const element = render({ currentStep: '9' });
    expect(one(element, 'heading').textContent).toBe('');
  });
});
