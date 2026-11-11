import { createElement } from 'lwc';
import LwcBuilderRenderer from 'c/lwcBuilderRenderer';
import loadComponent from '@salesforce/apex/LwcBuilderController.loadComponent';
import checkPermissions from '@salesforce/apex/LwcBuilderController.checkPermissions';
import { getRecord } from 'lightning/uiRecordApi';

jest.mock('@salesforce/apex/LwcBuilderController.loadComponent', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/LwcBuilderController.checkPermissions',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/LwcBuilderController.loadRecords', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/LwcBuilderController.loadChart', () => ({ default: jest.fn() }), {
  virtual: true
});

const DEFINITION = {
  schemaVersion: 1,
  sections: [
    {
      id: 's1',
      title: 'At a Glance',
      rows: [
        {
          id: 'r1',
          columns: [
            {
              id: 'c1',
              width: 6,
              blocks: [
                { id: 'b1', type: 'text', body: 'Always' },
                {
                  id: 'b2',
                  type: 'text',
                  body: 'Boston only',
                  visibility: {
                    type: 'field',
                    field: 'MailingCity',
                    operator: 'equals',
                    value: 'Boston'
                  }
                }
              ]
            },
            {
              id: 'c2',
              width: 6,
              blocks: [
                {
                  id: 'b3',
                  type: 'text',
                  body: 'Board only',
                  visibility: { type: 'permission', permission: 'Board_View' }
                }
              ]
            }
          ]
        }
      ]
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount(props) {
  const element = createElement('c-lwc-builder-renderer', { is: LwcBuilderRenderer });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const blocks = (element) => element.shadowRoot.querySelectorAll('c-lwc-builder-block');

describe('c-lwc-builder-renderer', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('loads a component by key and applies field and permission rules', async () => {
    loadComponent.mockResolvedValue({
      enabled: true,
      found: true,
      definition: JSON.stringify(DEFINITION)
    });
    checkPermissions.mockResolvedValue({ Board_View: true });
    const element = mount({
      componentKey: 'Donor_Snapshot',
      recordId: '003000000000001AAA',
      objectApiName: 'Contact'
    });
    await flush();

    expect(loadComponent).toHaveBeenCalledWith({ componentKey: 'Donor_Snapshot' });
    expect(checkPermissions).toHaveBeenCalledWith({ names: ['Board_View'] });
    expect(element.shadowRoot.querySelectorAll('lightning-card')).toHaveLength(1);
    expect(blocks(element)).toHaveLength(2);

    // eslint-disable-next-line @lwc/lwc/no-unexpected-wire-adapter-usages
    getRecord.emit({ fields: { MailingCity: { value: 'Boston' } } });
    await flush();
    expect(blocks(element)).toHaveLength(3);
    expect(blocks(element)[0].recordId).toBe('003000000000001AAA');
  });

  it('shows nothing when the setting is off or the component is missing', async () => {
    loadComponent.mockResolvedValue({ enabled: false, found: false });
    const element = mount({ componentKey: 'Donor_Snapshot' });
    await flush();
    expect(element.shadowRoot.querySelectorAll('lightning-card')).toHaveLength(0);
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();
  });

  it('shows a load failure as a message', async () => {
    loadComponent.mockRejectedValue({ body: { message: 'Refused' } });
    const element = mount({ componentKey: 'Donor_Snapshot' });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="error-message"]').message).toBe('Refused');
  });

  it('previews a definition it is given without loading one', async () => {
    const element = mount({ definition: { schemaVersion: 1, sections: [] } });
    await flush();
    expect(loadComponent).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
  });
});
