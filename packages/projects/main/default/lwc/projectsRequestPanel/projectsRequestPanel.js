import { LightningElement, api } from 'lwc';
import getRequest from '@salesforce/apex/ProjectRequestsController.getRequest';
import saveRequest from '@salesforce/apex/ProjectRequestsController.saveRequest';
import addComment from '@salesforce/apex/ProjectRequestsController.addComment';
import createTask from '@salesforce/apex/ProjectRequestsController.createTask';
import createChangeRequest from '@salesforce/apex/ProjectRequestsController.createChangeRequest';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { PRIORITIES, STATUSES, changesBetween, options } from 'c/projectsRequestsModel';

const PKG = 'Projects';

/**
 * One request for staff (D-201): triage (status, priority, owner, due date, project,
 * resolution), the comment thread with what the requester sees marked, Add Comment with Share
 * With Requester, and Create Task or Create Change Request on the request's project. Used in the
 * Requests tab and placeable on the Request record page. Fires `changed` after any save.
 */
export default class ProjectsRequestPanel extends LightningElement {
  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    this._recordId = value;
    if (this.connected) {
      this.load();
    }
  }

  _recordId;
  connected = false;
  helpReady = isHelpLoaded([PKG]);
  detail;
  draft = {};
  comment = '';
  share = false;
  isWorking = false;
  errorMessage;
  notice;
  statusOptions = options(STATUSES);
  priorityOptions = options(PRIORITIES);

  connectedCallback() {
    this.connected = true;
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  disconnectedCallback() {
    this.connected = false;
  }

  get labels() {
    return {
      status: helpText('Projects', 'Projects_Requests_Status'),
      priority: helpText('Projects', 'Projects_Requests_Priority'),
      owner: helpText('Projects', 'Projects_Requests_Owner'),
      due: helpText('Projects', 'Projects_Requests_DueDate'),
      project: helpText('Projects', 'Projects_Requests_Project'),
      resolution: helpText('Projects', 'Projects_Requests_Resolution'),
      save: helpText('Projects', 'Projects_Requests_Save'),
      comments: helpText('Projects', 'Projects_Requests_Comments'),
      noComments: helpText('Projects', 'Projects_Requests_NoComments'),
      comment: helpText('Projects', 'Projects_Requests_Comment'),
      share: helpText('Projects', 'Projects_Requests_Share'),
      addComment: helpText('Projects', 'Projects_Requests_AddComment'),
      shared: helpText('Projects', 'Projects_Requests_Shared'),
      internal: helpText('Projects', 'Projects_Requests_Internal'),
      fromRequester: helpText('Projects', 'Projects_Requests_FromRequester'),
      createTask: helpText('Projects', 'Projects_Requests_CreateTask'),
      createChange: helpText('Projects', 'Projects_Requests_CreateChange'),
      task: helpText('Projects', 'Projects_Requests_Task'),
      changeRequest: helpText('Projects', 'Projects_Requests_ChangeRequest'),
      requester: helpText('Projects', 'Projects_Requests_Requester'),
      channel: helpText('Projects', 'Projects_Requests_Channel'),
      satisfaction: helpText('Projects', 'Projects_Requests_Satisfaction')
    };
  }

  get value() {
    return { ...this.detail, ...this.draft };
  }

  get comments() {
    return (this.detail?.comments || []).map((row) => ({
      ...row,
      tag: row.fromRequester
        ? this.labels.fromRequester
        : row.shared
          ? this.labels.shared
          : this.labels.internal,
      boxClass: row.shared
        ? 'slds-box slds-theme_shade slds-var-m-bottom_x-small'
        : 'slds-box slds-var-m-bottom_x-small'
    }));
  }

  get hasComments() {
    return this.comments.length > 0;
  }

  get noProject() {
    return !this.value.projectId || this.isWorking;
  }

  get cannotCreateTask() {
    return this.noProject || Boolean(this.detail?.taskId);
  }

  get cannotCreateChange() {
    return (
      this.noProject || !this.detail?.changeRequestsEnabled || Boolean(this.detail?.changeRequestId)
    );
  }

  get cannotSave() {
    return this.isWorking || Object.keys(changesBetween(this.detail, this.draft)).length === 0;
  }

  get cannotComment() {
    return this.isWorking || !this.comment.trim();
  }

  async load() {
    if (!this._recordId) {
      return;
    }
    try {
      this.detail = await getRequest({ requestId: this._recordId });
      this.draft = {};
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  handleField(event) {
    const property = event.target.dataset.field;
    const value = event.detail.recordId !== undefined ? event.detail.recordId : event.detail.value;
    this.draft = { ...this.draft, [property]: value };
  }

  handleComment(event) {
    this.comment = event.detail.value || '';
  }

  handleShare(event) {
    this.share = event.detail.checked === true;
  }

  /** Runs one save, then shows `done`, reloads and tells the list; a refusal shows its words. */
  async run(work, done) {
    this.isWorking = true;
    try {
      await work();
      this.notice = done;
      this.errorMessage = undefined;
      await this.load();
      this.dispatchEvent(new CustomEvent('changed'));
    } catch (error) {
      this.notice = undefined;
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }

  handleSave() {
    return this.run(
      () =>
        saveRequest({
          requestId: this._recordId,
          changes: changesBetween(this.detail, this.draft)
        }),
      helpText('Projects', 'Projects_Requests_Saved')
    );
  }

  handleAddComment() {
    return this.run(
      async () => {
        await addComment({ requestId: this._recordId, body: this.comment, shared: this.share });
        this.comment = '';
        this.share = false;
      },
      helpText('Projects', 'Projects_Requests_CommentAdded')
    );
  }

  handleCreateTask() {
    return this.run(
      () => createTask({ requestId: this._recordId }),
      helpText('Projects', 'Projects_Requests_TaskCreated')
    );
  }

  handleCreateChange() {
    return this.run(
      () => createChangeRequest({ requestId: this._recordId }),
      helpText('Projects', 'Projects_Requests_ChangeCreated')
    );
  }
}
