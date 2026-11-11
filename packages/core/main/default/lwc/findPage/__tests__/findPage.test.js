import { createElement } from 'lwc';
import FindPage from 'c/findPage';
import * as navigation from 'lightning/navigation';

// Both views are stubs, so these tests see only which one the page shows.
jest.mock('c/findRecords', () => require('../../../../../test/jest-mocks/findPage/findRecords'));
jest.mock('c/gridTool', () => require('../../../../../test/jest-mocks/findPage/gridTool'));

const flush = () => Promise.resolve();

describe('c-find-page', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows Find unless the view is grid, then the Grid with the view key', async () => {
    const element = createElement('c-find-page', { is: FindPage });
    document.body.appendChild(element);
    navigation.CurrentPageReference.emit({ state: {} });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="find"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="grid"]')).toBeNull();

    navigation.CurrentPageReference.emit({ state: { c__view: 'grid' } });
    await flush();
    const grid = element.shadowRoot.querySelector('[data-id="grid"]');
    expect(grid).not.toBeNull();
    expect(grid.stateKey).toBe('c__view');
    expect(element.shadowRoot.querySelector('[data-id="find"]')).toBeNull();
  });
});
