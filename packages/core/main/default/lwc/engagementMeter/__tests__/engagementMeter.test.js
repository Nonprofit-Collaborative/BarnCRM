// The test wire adapters below are emitted to on purpose, which is how a wired component is
// driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import EngagementMeter from 'c/engagementMeter';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import isFeatureOn from '@salesforce/apex/EngagementScoreController.isFeatureOn';

jest.mock(
  '@salesforce/apex/EngagementScoreController.isFeatureOn',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const CONTACT_INFO = {
  apiName: 'Contact',
  fields: {
    Engagement_Score__c: { label: 'Engagement Score' },
    Engagement_Scored_On__c: { label: 'Scored On' }
  }
};

function personWith(score, scoredOn) {
  return {
    apiName: 'Contact',
    id: '003000000000001AAA',
    fields: {
      Engagement_Score__c: { value: score },
      Engagement_Scored_On__c: { value: scoredOn }
    }
  };
}

function build() {
  const element = createElement('c-engagement-meter', { is: EngagementMeter });
  element.recordId = '003000000000001AAA';
  document.body.appendChild(element);
  return element;
}

const flush = () => Promise.resolve();
const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-engagement-meter', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the score as a meter with the field labels and the day it was set', async () => {
    const element = build();
    isFeatureOn.emit(true);
    getObjectInfo.emit(CONTACT_INFO);
    getRecord.emit(personWith(64, '2026-11-11'));
    await flush();

    const meter = find(element, 'meter');
    expect(meter.value).toBe(64);
    expect(meter.valueText).toBe('64');
    expect(meter.label).toBe('Engagement Score');
    expect(find(element, 'title').textContent).toBe('Engagement Score');
    expect(find(element, 'help').helpKey).toBe('Core_EngagementMeter_Help');
    expect(find(element, 'scored-on').textContent).toContain('Scored On');
  });

  it('draws nothing while scoring is off', async () => {
    const element = build();
    isFeatureOn.emit(false);
    getObjectInfo.emit(CONTACT_INFO);
    getRecord.emit(personWith(64, '2026-11-11'));
    await flush();

    expect(find(element, 'meter')).toBeNull();
  });

  it('draws nothing for a person not scored yet, and a score of 0 still shows', async () => {
    const element = build();
    isFeatureOn.emit(true);
    getObjectInfo.emit(CONTACT_INFO);
    getRecord.emit(personWith(null, null));
    await flush();
    expect(find(element, 'meter')).toBeNull();

    getRecord.emit(personWith(0, '2026-11-11'));
    await flush();
    expect(find(element, 'meter').value).toBe(0);
  });
});
