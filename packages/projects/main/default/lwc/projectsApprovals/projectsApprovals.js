import { LightningElement } from 'lwc';
import getQueue from '@salesforce/apex/ProjectApprovalsController.getQueue';
import decide from '@salesforce/apex/ProjectApprovalsController.decide';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { groupApprovals } from 'c/projectsTimesheetModel';

const PKG = 'Projects';

/**
 * Approvals (PM-07, PM-08): the Submitted time and expenses of the person's projects (every
 * project with Manage Projects), grouped by person and week, approved or rejected with a reason
 * for a whole week or one line at a time. Who may decide is the entry's validation rule.
 */
export default class ProjectsApprovals extends LightningElement {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Projects_Approvals');
  queue;
  isLoading = true;
  isWorking = false;
  errorMessage;
  notice;
  reasons = {};
  open = {};

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  get labels() {
    return {
      title: helpText('Projects', 'Projects_Approvals_Title'),
      intro: helpText('Projects', 'Projects_Approvals_Intro'),
      off: helpText('Projects', 'Projects_Approvals_Off'),
      empty: helpText('Projects', 'Projects_Approvals_Empty'),
      approve: helpText('Projects', 'Projects_Approvals_Approve'),
      reject: helpText('Projects', 'Projects_Approvals_Reject'),
      reason: helpText('Projects', 'Projects_Approvals_Reason'),
      details: helpText('Projects', 'Projects_Approvals_Details'),
      date: helpText('Projects', 'Projects_Approvals_Date'),
      project: helpText('Projects', 'Projects_Approvals_Project'),
      what: helpText('Projects', 'Projects_Approvals_What'),
      notes: helpText('Projects', 'Projects_Approvals_Notes')
    };
  }

  get enabled() {
    return this.queue?.enabled === true;
  }

  get groups() {
    return groupApprovals(this.queue?.entries, this.queue?.expenses).map((group) => ({
      ...group,
      heading: helpText(
        'Projects',
        'Projects_Approvals_Week',
        group.person,
        group.weekStart,
        group.hours,
        group.amount
      ),
      idList: group.ids.join(','),
      reason: this.reasons[group.key] || '',
      shown: this.open[group.key] === true,
      lines: group.lines.map((line) => ({
        ...line,
        what:
          line.kind === 'time'
            ? `${line.Hours__c}${line.Task__r ? `: ${line.Task__r.Name}` : ''}`
            : `${line.Category__c} ${line.Amount__c}`,
        note: line.Notes__c || line.Description__c
      }))
    }));
  }

  get hasGroups() {
    return this.groups.length > 0;
  }

  async load() {
    this.isLoading = true;
    try {
      this.queue = await getQueue();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleReason(event) {
    this.reasons = { ...this.reasons, [event.target.dataset.group]: event.detail.value };
  }

  handleToggle(event) {
    const key = event.target.dataset.group;
    this.open = { ...this.open, [key]: !this.open[key] };
  }

  /** Decides the ids a button names (data-ids, comma separated), then reloads the queue. */
  async decide(event, approve) {
    const ids = event.target.dataset.ids.split(',');
    const reason = this.reasons[event.target.dataset.group];
    this.isWorking = true;
    try {
      const count = await decide({ ids, approve, reason: approve ? null : reason });
      this.notice = approve
        ? helpText('Projects', 'Projects_Approvals_Approved', count)
        : helpText('Projects', 'Projects_Approvals_Rejected', count);
      this.errorMessage = undefined;
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }

  handleApprove(event) {
    return this.decide(event, true);
  }

  handleReject(event) {
    return this.decide(event, false);
  }
}
