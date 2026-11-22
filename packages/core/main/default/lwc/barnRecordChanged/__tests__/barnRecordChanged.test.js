import { publish, subscribe, unsubscribe } from 'lightning/messageService';
import RECORD_CHANGED from '@salesforce/messageChannel/BarnCRM_Record_Changed__c';
import {
  publishRecordChanged,
  stopRecordChanged,
  subscribeRecordChanged
} from 'c/barnRecordChanged';

const CONTEXT = { id: 'context' };

describe('c-barn-record-changed', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  it('publishes the record id and source on the one channel', () => {
    publishRecordChanged(CONTEXT, 'a01', 'shiftSignups');
    expect(publish).toHaveBeenCalledWith(CONTEXT, RECORD_CHANGED, {
      recordId: 'a01',
      source: 'shiftSignups'
    });
  });

  it('publishes nothing without a record', () => {
    publishRecordChanged(CONTEXT, undefined, 'x');
    expect(publish).not.toHaveBeenCalled();
  });

  it('calls back only for the same record from another source', () => {
    let handler;
    subscribe.mockImplementation((context, channel, callback) => {
      handler = callback;
      return { id: 'sub' };
    });
    const onChange = jest.fn();
    const subscription = subscribeRecordChanged(CONTEXT, () => 'a01', 'me', onChange);
    expect(subscription).toEqual({ id: 'sub' });
    expect(subscribe).toHaveBeenCalledWith(CONTEXT, RECORD_CHANGED, expect.any(Function));

    handler({ recordId: 'a01', source: 'me' });
    handler({ recordId: 'a02', source: 'other' });
    handler(undefined);
    expect(onChange).not.toHaveBeenCalled();

    handler({ recordId: 'a01', source: 'other' });
    expect(onChange).toHaveBeenCalledTimes(1);
  });

  it('stops a subscription, and is safe with none', () => {
    stopRecordChanged(null);
    expect(unsubscribe).not.toHaveBeenCalled();
    stopRecordChanged({ id: 'sub' });
    expect(unsubscribe).toHaveBeenCalledWith({ id: 'sub' });
  });
});
