import { createElement } from 'lwc';
import HubRecurringFiles from 'c/hubRecurringFiles';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';

jest.mock(
  '@salesforce/apex/HubController.getHomeModel',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);

function build() {
  const element = createElement('c-hub-recurring-files', { is: HubRecurringFiles });
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-hub-recurring-files', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('lists the files that arrive regularly, says which were never imported, and opens Import', async () => {
    const element = build();
    getHomeModel.emit({
      recurringSources: [
        { id: 'a01', sourceName: 'Event sign-ups', templateName: 'Events', lastImportDate: null },
        {
          id: 'a02',
          sourceName: 'Monthly processor export',
          templateName: 'Processor',
          lastImportDate: '2026-08-31'
        }
      ]
    });
    await settle();

    const sources = element.shadowRoot.querySelectorAll('[data-id="recurring-source"]');
    expect(sources).toHaveLength(2);
    expect(sources[0].textContent).toContain('Event sign-ups');
    expect(sources[0].textContent).toContain('Core_HubHome_RecurringNever');
    expect(sources[1].querySelector('lightning-formatted-date-time')).not.toBeNull();

    element.shadowRoot.querySelector('[data-id="open-import"]').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Import' }
    });
  });

  it('shows nothing at all when no file is marked as arriving regularly', async () => {
    const element = build();
    getHomeModel.emit({ recurringSources: [] });
    await settle();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });
});
