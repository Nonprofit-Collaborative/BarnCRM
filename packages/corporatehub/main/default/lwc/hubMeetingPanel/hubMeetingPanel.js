import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getMeeting from '@salesforce/apex/HubBoardController.getMeeting';
import inviteBoard from '@salesforce/apex/HubBoardController.inviteBoard';
import setAttendance from '@salesforce/apex/HubBoardController.setAttendance';
import setMinutesStatus from '@salesforce/apex/HubBoardController.setMinutesStatus';
import openVoting from '@salesforce/apex/HubBoardController.openVoting';
import closeVoting from '@salesforce/apex/HubBoardController.closeVoting';
import sendPoll from '@salesforce/apex/HubBoardController.sendPoll';
import chooseTime from '@salesforce/apex/HubBoardController.chooseTime';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { ATTENDANCE, MINUTES_SUBMITTED, MINUTES_APPROVED, VOTING_OPEN } from 'c/corporateHubModel';

const HELP_PACKAGES = ['CorporateHub'];

/**
 * The Board Meeting panel (CH-10, CH-11, CH-16, CH-18, CH-20; ADR-0199
 * `0199-corporate-hub-board-governance.md` decision 13): Invite Board and attendance with the
 * quorum, the minutes' approval step with the members' portal approvals and packet reads, the
 * open action items carried from earlier meetings, the motions with Open Voting and Close Voting,
 * and the availability poll with Send Poll and Choose Time. The packet itself is Files on the
 * meeting and its Packet Link field.
 */
export default class HubMeetingPanel extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  view;
  isWorking = false;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  get meeting() {
    return (this.view && this.view.meeting) || {};
  }

  get labels() {
    const m = this.meeting;
    return {
      title: helpText('CorporateHub', 'CorporateHub_Meeting_Title'),
      invite: helpText('CorporateHub', 'CorporateHub_Meeting_Invite'),
      quorum: m.Quorum_Met__c
        ? helpText(
            'CorporateHub',
            'CorporateHub_Meeting_QuorumMet',
            m.Present_Count__c || 0,
            m.Quorum_Needed__c || 0
          )
        : helpText(
            'CorporateHub',
            'CorporateHub_Meeting_QuorumNotMet',
            m.Present_Count__c || 0,
            m.Quorum_Needed__c || 0
          ),
      noAttendees: helpText('CorporateHub', 'CorporateHub_Meeting_NoAttendees'),
      attendance: helpText('CorporateHub', 'CorporateHub_Meeting_Attendance'),
      portal: helpText(
        'CorporateHub',
        'CorporateHub_Meeting_PortalCounts',
        m.Packet_Reads__c || 0,
        m.Approvals_Count__c || 0
      ),
      minutes: helpText('CorporateHub', 'CorporateHub_Meeting_Minutes', m.Minutes_Status__c || ''),
      submit: helpText('CorporateHub', 'CorporateHub_Meeting_Submit'),
      approve: helpText('CorporateHub', 'CorporateHub_Meeting_Approve'),
      carried: helpText('CorporateHub', 'CorporateHub_Meeting_Carried'),
      noCarried: helpText('CorporateHub', 'CorporateHub_Meeting_NoCarried'),
      motions: helpText('CorporateHub', 'CorporateHub_Meeting_Motions'),
      openVoting: helpText('CorporateHub', 'CorporateHub_Meeting_OpenVoting'),
      closeVoting: helpText('CorporateHub', 'CorporateHub_Meeting_CloseVoting'),
      poll: helpText('CorporateHub', 'CorporateHub_Meeting_Poll'),
      sendPoll: helpText('CorporateHub', 'CorporateHub_Meeting_SendPoll'),
      choose: helpText('CorporateHub', 'CorporateHub_Meeting_Choose')
    };
  }

  async load() {
    try {
      this.view = await getMeeting({ meetingId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(
        error,
        helpText('CorporateHub', 'CorporateHub_Error_Generic')
      );
    }
  }

  get attendanceOptions() {
    return ATTENDANCE.map((value) => ({ label: value, value }));
  }

  get attendees() {
    return ((this.view && this.view.attendees) || []).map((row) => ({
      ...row,
      portalNote: [
        row.values.includes('packet')
          ? helpText('CorporateHub', 'CorporateHub_Meeting_ReadPacket')
          : '',
        row.values.includes('minutes')
          ? helpText('CorporateHub', 'CorporateHub_Meeting_Approved')
          : ''
      ]
        .filter(Boolean)
        .join(', ')
    }));
  }

  get hasAttendees() {
    return this.attendees.length > 0;
  }

  get canSubmit() {
    return this.meeting.Minutes_Status__c === 'Draft';
  }

  get canApprove() {
    return (
      Boolean(this.view && this.view.canManage) &&
      this.meeting.Minutes_Status__c === MINUTES_SUBMITTED
    );
  }

  get carried() {
    return (this.view && this.view.carried) || [];
  }

  get hasCarried() {
    return this.carried.length > 0;
  }

  get motions() {
    return ((this.view && this.view.motions) || []).map((row) => ({
      ...row,
      tally: helpText('CorporateHub', 'CorporateHub_Meeting_Tally', ...row.values),
      canOpen: row.status === 'Proposed',
      canClose: row.status === VOTING_OPEN
    }));
  }

  get hasMotions() {
    return this.motions.length > 0;
  }

  get pollTimes() {
    return ((this.view && this.view.pollTimes) || []).map((row) => ({
      ...row,
      answer: helpText('CorporateHub', 'CorporateHub_Meeting_PollYes', row.detail)
    }));
  }

  get hasPoll() {
    return this.pollTimes.length > 0;
  }

  get canSendPoll() {
    return this.hasPoll && !this.meeting.Poll_Open__c && !this.meeting.Start__c;
  }

  handleInvite() {
    return this.run(
      () => inviteBoard({ meetingId: this.recordId }),
      (added) => helpText('CorporateHub', 'CorporateHub_Meeting_Invited', added || 0)
    );
  }

  handleAttendance(event) {
    const attendeeId = event.target.dataset.rowId;
    return this.run(
      () => setAttendance({ attendeeId, attendance: event.detail.value }),
      () => helpText('CorporateHub', 'CorporateHub_Meeting_Saved')
    );
  }

  handleSubmit() {
    return this.minutes(MINUTES_SUBMITTED);
  }

  handleApprove() {
    return this.minutes(MINUTES_APPROVED);
  }

  minutes(status) {
    return this.run(
      () => setMinutesStatus({ meetingId: this.recordId, status }),
      () => helpText('CorporateHub', 'CorporateHub_Meeting_Saved')
    );
  }

  handleOpenVoting(event) {
    const motionId = event.target.dataset.rowId;
    return this.run(
      () => openVoting({ motionId }),
      (count) => helpText('CorporateHub', 'CorporateHub_Meeting_VotingOpened', count || 0)
    );
  }

  handleCloseVoting(event) {
    const motionId = event.target.dataset.rowId;
    return this.run(
      () => closeVoting({ motionId }),
      (result) => helpText('CorporateHub', 'CorporateHub_Meeting_VotingClosed', result)
    );
  }

  handleSendPoll() {
    return this.run(
      () => sendPoll({ meetingId: this.recordId }),
      () => helpText('CorporateHub', 'CorporateHub_Meeting_PollSent')
    );
  }

  handleChoose(event) {
    const option = Number(event.target.dataset.rowId);
    return this.run(
      () => chooseTime({ meetingId: this.recordId, option }),
      () => helpText('CorporateHub', 'CorporateHub_Meeting_Saved')
    );
  }

  /** One server call, then a toast and the record and panel refreshed. */
  async run(call, success) {
    this.isWorking = true;
    try {
      const result = await call();
      this.dispatchEvent(new ShowToastEvent({ message: success(result), variant: 'success' }));
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(
        error,
        helpText('CorporateHub', 'CorporateHub_Error_Generic')
      );
    } finally {
      this.isWorking = false;
    }
  }
}
