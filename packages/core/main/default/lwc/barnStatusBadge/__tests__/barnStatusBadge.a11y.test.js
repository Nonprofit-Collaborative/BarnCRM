import { createElement } from 'lwc';
import BarnStatusBadge from 'c/barnStatusBadge';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-status-badge accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-status-badge', { is: BarnStatusBadge });
    Object.assign(element, { status: 'success', label: 'Paid' });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
