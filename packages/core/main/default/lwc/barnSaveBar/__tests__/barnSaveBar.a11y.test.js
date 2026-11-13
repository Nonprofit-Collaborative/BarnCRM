import { createElement } from 'lwc';
import BarnSaveBar from 'c/barnSaveBar';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-save-bar accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-save-bar', { is: BarnSaveBar });
    Object.assign(element, { dirtyCount: 2 });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
