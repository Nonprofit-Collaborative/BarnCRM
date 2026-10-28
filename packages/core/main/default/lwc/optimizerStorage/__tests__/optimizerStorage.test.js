import { createElement } from 'lwc';
import OptimizerStorage from 'c/optimizerStorage';
import getStorage from '@salesforce/apex/OrgOptimizerStorageController.getStorage';

jest.mock(
  '@salesforce/apex/OrgOptimizerStorageController.getStorage',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_OrgOptimizer_LimitUsage',
  () => ({ default: '{0} of {1} ({2}%)' }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/label/c.Core_OrgOptimizer_MoreThan', () => ({ default: 'More than {0}' }), {
  virtual: true
});

const STORAGE = {
  countCap: 10000,
  limits: [{ name: 'DataStorageMB', used: 150, max: 200, percent: 75 }],
  ownObjects: [
    {
      apiName: 'Import_Row__c',
      label: 'Import Rows',
      records: 10000,
      moreThan: true,
      estimatedMB: 19.5
    },
    { apiName: 'Error_Log__c', label: 'Error Logs', records: 12, moreThan: false, estimatedMB: 0 }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  const element = createElement('c-optimizer-storage', { is: OptimizerStorage });
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

describe('c-optimizer-storage', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows each limit with its use and the own objects with capped counts', async () => {
    getStorage.mockResolvedValue(STORAGE);
    const element = await render();

    const limit = element.shadowRoot.querySelector('[data-id="DataStorageMB"]');
    expect(limit.textContent).toContain('150 of 200 (75%)');
    expect(limit.querySelector('lightning-progress-bar').value).toBe(75);
    const table = element.shadowRoot.querySelector('[data-id="own"]');
    expect(table.data[0].recordsText).toBe('More than 10000');
    expect(table.data[1].recordsText).toBe('12');
    expect(limit.querySelector('[data-id="near-limit"]')).toBeNull();
  });

  it('marks a limit near its end, and tells the page how full data storage is', async () => {
    getStorage.mockResolvedValue({
      ...STORAGE,
      limits: [{ name: 'DataStorageMB', used: 180, max: 200, percent: 90 }]
    });
    const summary = jest.fn();
    const element = createElement('c-optimizer-storage', { is: OptimizerStorage });
    element.addEventListener('summary', summary);
    document.body.appendChild(element);
    await flush();
    await flush();

    const limit = element.shadowRoot.querySelector('[data-id="DataStorageMB"]');
    expect(limit.querySelector('[data-id="near-limit"]')).not.toBeNull();
    expect(summary.mock.calls[0][0].detail).toEqual({ dataStoragePercent: 90 });
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('shows the unexpected-error label when the failure has no message', async () => {
    getStorage.mockRejectedValue('boom');
    const element = await render();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toBe(
      'c.Core_UnexpectedError'
    );
  });

  it('shows the refusal and reads again on Refresh', async () => {
    getStorage.mockRejectedValue({ body: { message: 'Needs the permission.' } });
    const element = await render();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toBe(
      'Needs the permission.'
    );

    getStorage.mockResolvedValue(STORAGE);
    element.shadowRoot.querySelector('[data-id="refresh"]').click();
    await flush();
    await flush();
    expect(getStorage).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
  });
});
