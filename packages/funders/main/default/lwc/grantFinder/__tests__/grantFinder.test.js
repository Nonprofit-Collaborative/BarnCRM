import { createElement } from 'lwc';
import GrantFinder from 'c/grantFinder';
import getStatus from '@salesforce/apex/GrantFinderController.getStatus';
import search from '@salesforce/apex/GrantFinderController.search';
import save from '@salesforce/apex/GrantFinderController.save';

jest.mock('@salesforce/apex/GrantFinderController.getStatus', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GrantFinderController.search', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GrantFinderController.save', () => ({ default: jest.fn() }), {
  virtual: true
});

const LISTING = {
  id: '350001',
  listingNumber: 'ED-GRANTS-001',
  title: 'Literacy for Rural Schools',
  agency: 'Department of Education',
  status: 'posted',
  openDate: '2026-11-01',
  closeDate: '2027-01-15',
  assistanceListing: '84.305',
  url: 'https://www.grants.gov/search-results-detail/350001',
  grantId: null
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(status) {
  getStatus.mockResolvedValue(status);
  const element = createElement('c-grant-finder', { is: GrantFinder });
  document.body.appendChild(element);
  await flush();
  return element;
}

async function searchFor(element, words) {
  const input = element.shadowRoot.querySelector('[data-id="keyword"]');
  input.value = words;
  input.dispatchEvent(new CustomEvent('change'));
  await flush();
  element.shadowRoot.querySelector('[data-id="search"]').click();
  await flush();
}

describe('c-grant-finder', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says it is off, with no search, when the setting is off', async () => {
    const element = await render({ enabled: false, canSave: true });
    expect(element.shadowRoot.querySelector('[data-id="off"]').textContent).toBe(
      'c.Funders_Finder_Off'
    );
    expect(element.shadowRoot.querySelector('[data-id="search"]')).toBeNull();
  });

  it('searches the words typed and saves a listing to the pipeline', async () => {
    search.mockResolvedValue([LISTING]);
    save.mockResolvedValue('a01000000000001');
    const element = await render({ enabled: true, canSave: true });
    await searchFor(element, '  literacy ');
    expect(search).toHaveBeenCalledWith({ keyword: 'literacy', statuses: ['posted'] });
    expect(element.shadowRoot.querySelectorAll('[data-id="listing"]')).toHaveLength(1);

    element.shadowRoot.querySelector('[data-id="350001"]').click();
    await flush();
    expect(JSON.parse(save.mock.calls[0][0].listing).title).toBe('Literacy for Rural Schools');
    const saved = element.shadowRoot.querySelector('[data-id="saved"]');
    expect(saved.getAttribute('href')).toBe('/a01000000000001');
    expect(element.shadowRoot.querySelector('[data-id="350001"]')).toBeNull();
  });

  it('offers no save to a person who cannot create grants', async () => {
    search.mockResolvedValue([LISTING]);
    const element = await render({ enabled: true, canSave: false });
    await searchFor(element, 'literacy');
    expect(element.shadowRoot.querySelectorAll('[data-id="listing"]')).toHaveLength(1);
    expect(element.shadowRoot.querySelector('[data-id="350001"]')).toBeNull();
  });

  it('says so when nothing matches, and shows the error when Grants.gov fails', async () => {
    search.mockResolvedValueOnce([]);
    const element = await render({ enabled: true, canSave: true });
    await searchFor(element, 'nothing');
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();

    search.mockRejectedValueOnce({ body: { message: 'Grants.gov did not answer.' } });
    element.shadowRoot.querySelector('[data-id="search"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="error-message"]').textContent).toBe(
      'Grants.gov did not answer.'
    );
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();
  });
});
