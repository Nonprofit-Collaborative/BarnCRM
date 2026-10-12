import { createElement } from 'lwc';
import ErrorDigestJob from 'c/errorDigestJob';
import getDigest from '@salesforce/apex/ErrorDigestController.getDigest';

jest.mock(
  '@salesforce/apex/ErrorDigestController.getDigest',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/ErrorDigestController.setSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/ErrorDigestController.sendNow', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: false }), {
  virtual: true
});

describe('c-error-digest-job without the settings permission', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('lets someone read it but not change it', async () => {
    const element = createElement('c-error-digest-job', { is: ErrorDigestJob });
    document.body.appendChild(element);
    getDigest.emit({
      canManage: false,
      scheduled: true,
      nextRunAt: '2026-09-25T07:00:00.000Z',
      recipients: ['Maria Lopez'],
      toAdministrators: true
    });
    await Promise.resolve();

    const root = element.shadowRoot;
    expect(root.querySelector('[data-id="schedule-button"]').disabled).toBe(true);
    expect(root.querySelector('[data-id="send-now"]').disabled).toBe(true);
    expect(root.querySelector('[data-id="read-only"]')).not.toBeNull();
  });
});
