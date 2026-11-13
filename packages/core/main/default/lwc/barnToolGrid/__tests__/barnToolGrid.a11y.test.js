import { createElement } from 'lwc';
import BarnToolGrid from 'c/barnToolGrid';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-tool-grid accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks', async () => {
    const element = createElement('c-barn-tool-grid', { is: BarnToolGrid });
    Object.assign(element, {
      groups: [
        {
          name: 'in',
          label: 'Bring Data In',
          tiles: [
            {
              name: 'import',
              label: 'Import',
              description: 'From a spreadsheet.',
              iconName: 'standard:data_streams'
            }
          ]
        }
      ]
    });
    document.body.appendChild(element);
    await Promise.resolve();
    await expectAccessible(element);
  });
});
