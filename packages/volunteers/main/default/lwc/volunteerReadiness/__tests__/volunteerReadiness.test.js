import { createElement } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import VolunteerReadiness from 'c/volunteerReadiness';
import getReadiness from '@salesforce/apex/VolunteerReadinessController.getReadiness';
import { refreshApex } from '@salesforce/apex';

jest.mock(
  '@salesforce/apex/VolunteerReadinessController.getReadiness',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

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
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);

const PERSON_ID = '003000000000001AAA';
const CHECK_ID = 'a0V000000000001AAA';

const READY = {
  canSee: true,
  steps: [
    {
      type: 'Application',
      typeLabel: 'Application',
      requirementId: null,
      statusLabel: null,
      completedDate: null,
      expires: null,
      isCurrent: false
    },
    {
      type: 'Background check',
      typeLabel: 'Background check',
      requirementId: CHECK_ID,
      statusLabel: 'Completed',
      completedDate: '2026-10-01',
      expires: '2028-10-01',
      isCurrent: true
    }
  ]
};

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function render() {
  const element = createElement('c-volunteer-readiness', { is: VolunteerReadiness });
  element.recordId = PERSON_ID;
  document.body.appendChild(element);
  return element;
}

describe('c-volunteer-readiness', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows nothing until the answer arrives', () => {
    const element = render();
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('lists each type with its latest step or Not started, and whether it is current', async () => {
    const element = render();
    getReadiness.emit(READY);
    await flush();

    const steps = element.shadowRoot.querySelectorAll('li.step');
    expect(steps).toHaveLength(2);

    expect(steps[0].querySelector('a')).toBeNull();
    expect(steps[0].querySelector('.step-type').textContent).toBe('Application');
    expect(steps[0].querySelector('.status').textContent).toBe('c.Volunteers_Readiness_NotStarted');
    expect(steps[0].querySelector('.state').textContent).toBe('c.Volunteers_Readiness_NotCurrent');

    const link = steps[1].querySelector('a.step-type');
    expect(link.textContent).toBe('Background check');
    expect(link.getAttribute('href')).toBe(`/${CHECK_ID}`);
    expect(steps[1].querySelector('.status').textContent).toBe('Completed');
    expect(steps[1].querySelector('.state').textContent).toBe('c.Volunteers_Readiness_Current');
    expect(steps[1].querySelector('.state').className).toContain('slds-theme_success');
    expect(steps[1].querySelector('.completed lightning-formatted-date-time').value).toBe(
      '2026-10-01'
    );
    expect(steps[1].querySelector('.expires lightning-formatted-date-time').value).toBe(
      '2028-10-01'
    );
  });

  it('shows no card to someone who cannot see requirements, or on a household', async () => {
    const element = render();
    getReadiness.emit({ canSee: false, steps: [] });
    await flush();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('opens a step when its type is clicked', async () => {
    const element = render();
    getReadiness.emit(READY);
    await flush();

    element.shadowRoot.querySelector('a.step-type').click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__recordPage',
      attributes: { recordId: CHECK_ID, actionName: 'view' }
    });
  });

  it('refreshes on demand, with a labelled button', async () => {
    const element = render();
    getReadiness.emit(READY);
    await flush();

    const button = element.shadowRoot.querySelector('lightning-button-icon.refresh');
    expect(button.alternativeText).toBe('c.Volunteers_Readiness_Refresh');
    button.click();

    expect(refreshApex).toHaveBeenCalled();
  });

  it('says so, in a generic message, to a user who can see requirements when it cannot load', async () => {
    const element = render();
    getObjectInfo.emit({ queryable: true });
    getReadiness.error({ body: { message: 'FIELD_CUSTOM_VALIDATION_EXCEPTION secret detail' } });
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent).toBe('c.Volunteers_Readiness_LoadFailed');
    expect(element.shadowRoot.textContent).not.toContain('secret detail');
  });

  it('says so when the failure arrives before the permission answer', async () => {
    const element = render();
    getReadiness.error();
    await flush();
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();

    getObjectInfo.emit({ queryable: true });
    await flush();

    expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
  });

  it('shows nothing when it cannot load for a user who cannot see requirements', async () => {
    const element = render();
    getObjectInfo.emit({ queryable: false });
    getReadiness.error();
    await flush();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
    expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
  });

  it('shows nothing when it cannot load and the object cannot be read at all', async () => {
    const element = render();
    getObjectInfo.error();
    getReadiness.error();
    await flush();

    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });
});
