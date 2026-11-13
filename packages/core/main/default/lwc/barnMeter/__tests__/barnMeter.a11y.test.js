import { createElement } from 'lwc';
import BarnMeter from 'c/barnMeter';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-meter accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-meter', { is: BarnMeter });
    Object.assign(element, { label: 'Goal', value: 40, max: 100, valueText: '40 of 100' });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
