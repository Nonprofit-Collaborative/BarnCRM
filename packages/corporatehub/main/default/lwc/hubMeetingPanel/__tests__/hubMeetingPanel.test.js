import { createElement } from 'lwc';
import HubMeetingPanel from 'c/hubMeetingPanel';
import getMeeting from '@salesforce/apex/HubBoardController.getMeeting';
import inviteBoard from '@salesforce/apex/HubBoardController.inviteBoard';
import setAttendance from '@salesforce/apex/HubBoardController.setAttendance';
import setMinutesStatus from '@salesforce/apex/HubBoardController.setMinutesStatus';
import openVoting from '@salesforce/apex/HubBoardController.openVoting';
import chooseTime from '@salesforce/apex/HubBoardController.chooseTime';

jest.mock('@salesforce/apex/HubBoardController.getMeeting', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubBoardController.inviteBoard', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubBoardController.setAttendance', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubBoardController.setMinutesStatus', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubBoardController.openVoting', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubBoardController.closeVoting', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubBoardController.sendPoll', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubBoardController.chooseTime', () => ({ default: jest.fn() }), {
  virtual: true
});

const RECORD_ID = 'a07000000000001AAA';
const VIEW = {
  meeting: {
    Minutes_Status__c: 'Submitted for Approval',
    Quorum_Met__c: true,
    Present_Count__c: 2,
    Quorum_Needed__c: 2,
    Packet_Reads__c: 1,
    Approvals_Count__c: 1,
    Poll_Open__c: false
  },
  attendees: [
    { id: 'm1', name: 'Ade', status: 'Present', flag: true, values: ['packet', 'minutes'] }
  ],
  motions: [{ id: 'v1', name: 'Approve the budget', status: 'Proposed', values: ['0', '0', '0'] }],
  carried: [{ id: 'i1', name: 'Send the audit letter', status: 'Ade' }],
  pollTimes: [{ id: '1', name: '1/2/2027 9:00 AM', detail: '2' }],
  canManage: true
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}
const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function mount() {
  const element = createElement('c-hub-meeting-panel', { is: HubMeetingPanel });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  return element;
}

describe('c-hub-meeting-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows quorum, attendees, carried items, motions and the poll', async () => {
    getMeeting.mockResolvedValue(VIEW);
    const element = mount();
    await flush();
    expect(getMeeting).toHaveBeenCalledWith({ meetingId: RECORD_ID });
    expect(find(element, 'quorum')).not.toBeNull();
    expect(find(element, 'attendees')).not.toBeNull();
    expect(find(element, 'carried')).not.toBeNull();
    expect(find(element, 'open-voting')).not.toBeNull();
    expect(find(element, 'approve')).not.toBeNull();
    expect(find(element, 'submit')).toBeNull();
    expect(find(element, 'choose')).not.toBeNull();
  });

  it('invites the board, sets attendance, approves minutes, opens voting and chooses a time', async () => {
    getMeeting.mockResolvedValue(VIEW);
    inviteBoard.mockResolvedValue(3);
    setAttendance.mockResolvedValue();
    setMinutesStatus.mockResolvedValue();
    openVoting.mockResolvedValue(2);
    chooseTime.mockResolvedValue();
    const element = mount();
    await flush();
    find(element, 'invite').click();
    await flush();
    expect(inviteBoard).toHaveBeenCalledWith({ meetingId: RECORD_ID });
    find(element, 'attendance').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Absent' } })
    );
    await flush();
    expect(setAttendance).toHaveBeenCalledWith({ attendeeId: 'm1', attendance: 'Absent' });
    find(element, 'approve').click();
    await flush();
    expect(setMinutesStatus).toHaveBeenCalledWith({ meetingId: RECORD_ID, status: 'Approved' });
    find(element, 'open-voting').click();
    await flush();
    expect(openVoting).toHaveBeenCalledWith({ motionId: 'v1' });
    find(element, 'choose').click();
    await flush();
    expect(chooseTime).toHaveBeenCalledWith({ meetingId: RECORD_ID, option: 1 });
  });

  it('offers staff Submit, not Approve, while minutes are a draft', async () => {
    getMeeting.mockResolvedValue({
      ...VIEW,
      canManage: false,
      meeting: { ...VIEW.meeting, Minutes_Status__c: 'Draft' },
      attendees: [],
      motions: [],
      carried: [],
      pollTimes: []
    });
    const element = mount();
    await flush();
    expect(find(element, 'submit')).not.toBeNull();
    expect(find(element, 'approve')).toBeNull();
    expect(find(element, 'no-attendees')).not.toBeNull();
    expect(find(element, 'no-carried')).not.toBeNull();
  });
});
