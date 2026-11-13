import { createElement } from 'lwc';
import BarnHelp from 'c/barnHelp';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-help accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-help', { is: BarnHelp });
    Object.assign(element, {
      content: 'What this page does.',
      learnMoreUrl: 'https://example.org/help',
      learnMoreLabel: 'Learn More'
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
