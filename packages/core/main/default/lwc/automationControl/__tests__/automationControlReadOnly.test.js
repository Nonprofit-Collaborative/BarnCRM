import { createElement } from 'lwc';
import AutomationControl from 'c/automationControl';
import getPage from '@salesforce/apex/AutomationControlController.getPage';

jest.mock(
  '@salesforce/apex/AutomationControlController.getPage',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/AutomationControlController.pauseAll', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/AutomationControlController.resumeAll',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AutomationControlController.setEnabled',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// David has no Manage BarnCRM Settings permission, so the page opens read only.
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});

jest.mock(
  '@salesforce/label/c.Core_AutomationControl_ReadOnly',
  () => ({
    default:
      'You can read this page but not change it. Ask your administrator for the Manage BarnCRM Settings permission.'
  }),
  { virtual: true }
);

const PAGE = {
  paused: false,
  pausedUntil: null,
  canManage: false,
  pauseHourOptions: [1, 2, 4, 8, 24],
  automations: [
    {
      recordId: '001000000000000AAA',
      automationName: 'Household_Naming',
      label: 'Household naming',
      description: 'Keeps household names and greetings up to date.',
      objectName: 'Contact',
      enabled: true
    }
  ]
};

describe('c-automation-control without the settings permission', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('names the permission and disables every control', async () => {
    const element = createElement('c-automation-control', { is: AutomationControl });
    document.body.appendChild(element);
    getPage.emit(PAGE);
    await Promise.resolve();

    const notice = element.shadowRoot.querySelector('[data-id="read-only-notice"]');
    expect(notice).not.toBeNull();
    expect(notice.textContent).toContain('Manage BarnCRM Settings');
    expect(element.shadowRoot.querySelector('[data-id="pause-button"]').disabled).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="resume-button"]').disabled).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="pause-hours"]').disabled).toBe(true);
    expect(element.shadowRoot.querySelector('.automation-toggle').disabled).toBe(true);
  });
});
