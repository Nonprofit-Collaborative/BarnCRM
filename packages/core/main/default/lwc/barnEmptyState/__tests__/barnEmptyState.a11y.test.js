import { createElement } from 'lwc';
import BarnEmptyState from 'c/barnEmptyState';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-empty-state accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-empty-state', { is: BarnEmptyState });
    Object.assign(element, { heading: 'No Gifts Yet', message: 'Add the first gift.' });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
