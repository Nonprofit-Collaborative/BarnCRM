import { createElement } from 'lwc';
import BarnNotice from 'c/barnNotice';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-notice accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-notice', { is: BarnNotice });
    Object.assign(element, {
      variant: 'warning',
      title: 'Check Your Settings',
      message: 'Two settings need a value.',
      actionLabel: 'Open Settings',
      actionHref: '/lightning/n/Settings'
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
