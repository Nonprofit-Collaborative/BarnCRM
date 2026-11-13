import { createElement } from 'lwc';
import BarnToolTile from 'c/barnToolTile';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-tool-tile accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks, enabled and disabled', async () => {
    for (const props of [
      { name: 'find', label: 'Find', description: 'Find records.', iconName: 'standard:search' },
      { name: 'merge', label: 'Merge', disabled: true, disabledReason: 'Turn on Duplicates.' }
    ]) {
      const element = createElement('c-barn-tool-tile', { is: BarnToolTile });
      Object.assign(element, props);
      document.body.appendChild(element);
      // eslint-disable-next-line no-await-in-loop
      await Promise.resolve();
      // eslint-disable-next-line no-await-in-loop
      await expectAccessible(element);
    }
  });
});
