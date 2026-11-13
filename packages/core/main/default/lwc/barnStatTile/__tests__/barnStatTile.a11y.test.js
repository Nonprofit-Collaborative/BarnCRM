import { createElement } from 'lwc';
import BarnStatTile from 'c/barnStatTile';
import { expectAccessible } from 'barn/a11y';

describe('c-barn-stat-tile accessibility', () => {
  afterEach(() => document.body.replaceChildren());

  it('passes the accessibility checks, as a plain tile and as a link', async () => {
    for (const props of [
      { label: 'Gifts This Year', value: 42, iconName: 'custom:custom17' },
      { label: 'Open Asks', value: 3, href: '/lightning/n/Ask_Pipeline', badgeLabel: 'New' }
    ]) {
      const element = createElement('c-barn-stat-tile', { is: BarnStatTile });
      Object.assign(element, props);
      document.body.appendChild(element);
      // eslint-disable-next-line no-await-in-loop
      await Promise.resolve();
      // eslint-disable-next-line no-await-in-loop
      await expectAccessible(element);
    }
  });
});
