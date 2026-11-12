import { createElement } from 'lwc';
import CorporateHubHome from 'c/corporateHubHome';
import getHome from '@salesforce/apex/CorporateHubController.getHome';
import acknowledge from '@salesforce/apex/CorporateHubController.acknowledge';
import addMissingTemplates from '@salesforce/apex/CorporateHubController.addMissingTemplates';

jest.mock('@salesforce/apex/CorporateHubController.getHome', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CorporateHubController.acknowledge', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/CorporateHubController.addMissingTemplates',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const HOME = {
  canManage: true,
  requests: [
    {
      id: 'a03000000000001AAA',
      name: 'Conflict of Interest',
      due: '2000-01-01',
      recordId: 'a02000000000001AAA'
    }
  ],
  obligations: [
    { id: 'a04000000000001AAA', name: 'Annual report', due: '2999-01-01', detail: 'Maria' }
  ],
  agreements: []
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount() {
  const element = createElement('c-corporate-hub-home', { is: CorporateHubHome });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-corporate-hub-home', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the request, the obligation and an empty agreements list', async () => {
    getHome.mockResolvedValue(HOME);
    const element = mount();
    await flush();

    const request = find(element, 'requests');
    expect(request.querySelector('a').getAttribute('href')).toBe(
      '/lightning/r/a02000000000001AAA/view'
    );
    expect(request.textContent).toContain('c.CorporateHub_Due_Overdue');
    expect(request.querySelector('div.slds-text-color_error')).not.toBeNull();
    expect(find(element, 'obligations').textContent).toContain('Annual report');
    expect(find(element, 'no-agreements')).not.toBeNull();
    expect(find(element, 'add-templates')).not.toBeNull();
    expect(find(element, 'privacy')).toBeNull();
  });

  it('shows open data subject requests and unreported breaches under Data Protection', async () => {
    getHome.mockResolvedValue({
      ...HOME,
      privacy: [
        {
          id: 'a05000000000001AAA',
          name: 'Data subject request: DSR-00001',
          due: '2000-01-01',
          status: 'Access'
        }
      ]
    });
    const element = mount();
    await flush();

    const privacy = find(element, 'privacy');
    expect(privacy.textContent).toContain('c.CorporateHub_Home_Privacy');
    expect(privacy.textContent).toContain('DSR-00001');
    expect(privacy.querySelector('a').getAttribute('href')).toBe(
      '/lightning/r/a05000000000001AAA/view'
    );
    expect(privacy.querySelector('div.slds-text-color_error')).not.toBeNull();
  });

  it('records I Have Read This and reloads', async () => {
    getHome.mockResolvedValue(HOME);
    acknowledge.mockResolvedValue(undefined);
    const element = mount();
    await flush();

    find(element, 'have-read').click();
    await flush();

    expect(acknowledge).toHaveBeenCalledWith({ acknowledgmentId: 'a03000000000001AAA' });
    expect(getHome).toHaveBeenCalledTimes(2);
  });

  it('adds missing templates for a manager and hides the button from others', async () => {
    getHome.mockResolvedValue(HOME);
    addMissingTemplates.mockResolvedValue(3);
    const element = mount();
    await flush();
    find(element, 'add-templates').click();
    await flush();
    expect(addMissingTemplates).toHaveBeenCalled();

    getHome.mockResolvedValue({ ...HOME, canManage: false });
    const other = mount();
    await flush();
    expect(find(other, 'add-templates')).toBeNull();
  });

  it('shows the error when the page cannot load', async () => {
    getHome.mockRejectedValue({ body: { message: 'No access' } });
    const element = mount();
    await flush();

    expect(find(element, 'error-message').message).toBe('No access');
  });
});
