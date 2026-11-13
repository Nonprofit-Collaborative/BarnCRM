import { createElement } from 'lwc';
import BarnStepFlow from 'c/barnStepFlow';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-step-flow accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-step-flow', { is: BarnStepFlow });
    Object.assign(element, {
      steps: [
        { value: '1', label: 'Choose File Type' },
        { value: '2', label: 'Upload File' }
      ],
      currentStep: '2',
      canGoBack: true
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
