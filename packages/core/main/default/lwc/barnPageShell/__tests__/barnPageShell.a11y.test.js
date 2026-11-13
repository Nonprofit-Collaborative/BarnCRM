import { createElement } from 'lwc';
import BarnPageShell from 'c/barnPageShell';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-page-shell accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-page-shell', { is: BarnPageShell });
    Object.assign(element, {
      iconName: 'custom:custom1',
      title: 'Gifts',
      purpose: 'Every gift, in one place.',
      helpLabel: 'About This Page',
      statusMessage: 'Saved.'
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
