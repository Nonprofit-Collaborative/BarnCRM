import { LightningElement } from 'lwc';
import getStaffing from '@salesforce/apex/ProjectStaffingController.getStaffing';
import getAllocation from '@salesforce/apex/ProjectStaffingController.getAllocation';
import fill from '@salesforce/apex/ProjectStaffingController.fill';
import saveResource from '@salesforce/apex/ProjectStaffingController.saveResource';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { rankCandidates, skillList } from 'c/projectsAllocationModel';

const PKG = 'Projects';
const BLANK = { userId: undefined, skills: [], capacity: undefined, role: '', active: true };

/**
 * The Staffing page (PM-09, R-PM15): open resource requests with Fill, which lists people with
 * every requested skill first, then those whose default role is the request's role, then the most
 * free capacity in its dates, and the people who can be staffed with their skills and capacity.
 * Ranking is worked out here by `c/projectsAllocationModel`.
 */
export default class ProjectsStaffing extends LightningElement {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Project_Resource__c');
  staffing;
  filling;
  candidates = [];
  draft = { ...BLANK };
  isLoading = true;
  isWorking = false;
  errorMessage;
  notice;

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
      title: helpText('Projects', 'Projects_Staffing_Title'),
      intro: helpText('Projects', 'Projects_Staffing_Intro'),
      off: helpText('Projects', 'Projects_Staffing_Off'),
      requests: helpText('Projects', 'Projects_Staffing_Requests'),
      noRequests: helpText('Projects', 'Projects_Staffing_NoRequests'),
      project: helpText('Projects', 'Projects_Staffing_Project'),
      role: helpText('Projects', 'Projects_Staffing_Role'),
      skills: helpText('Projects', 'Projects_Staffing_Skills'),
      hours: helpText('Projects', 'Projects_Staffing_Hours'),
      dates: helpText('Projects', 'Projects_Staffing_Dates'),
      fill: helpText('Projects', 'Projects_Staffing_Fill'),
      candidatesHelp: helpText('Projects', 'Projects_Staffing_CandidatesHelp'),
      noCandidates: helpText('Projects', 'Projects_Staffing_NoCandidates'),
      person: helpText('Projects', 'Projects_Staffing_Person'),
      skillsMatched: helpText('Projects', 'Projects_Staffing_SkillsMatched'),
      roleMatch: helpText('Projects', 'Projects_Staffing_RoleMatch'),
      free: helpText('Projects', 'Projects_Staffing_Free'),
      assign: helpText('Projects', 'Projects_Staffing_Assign'),
      close: helpText('Projects', 'Projects_Staffing_Close'),
      resources: helpText('Projects', 'Projects_Staffing_Resources'),
      noResources: helpText('Projects', 'Projects_Staffing_NoResources'),
      capacity: helpText('Projects', 'Projects_Staffing_Capacity'),
      defaultRole: helpText('Projects', 'Projects_Staffing_DefaultRole'),
      active: helpText('Projects', 'Projects_Staffing_Active'),
      edit: helpText('Projects', 'Projects_Staffing_Edit'),
      save: helpText('Projects', 'Projects_Staffing_Save'),
      newResource: helpText('Projects', 'Projects_Staffing_NewResource')
    };
  }

  get enabled() {
    return this.staffing?.enabled === true;
  }

  get isOff() {
    return this.staffing !== undefined && !this.enabled;
  }

  get skillOptions() {
    return (this.staffing?.skills || []).map((skill) => ({ label: skill, value: skill }));
  }

  get requests() {
    return (this.staffing?.requests || []).map((row) => ({
      ...row,
      href: `/lightning/r/${row.Project__c}/view`,
      projectName: row.Project__r?.Name,
      dates: `${row.Start_Date__c} - ${row.End_Date__c}`,
      skills: skillList(row.Skills__c).join(', ')
    }));
  }

  get hasRequests() {
    return this.requests.length > 0;
  }

  get resources() {
    return (this.staffing?.resources || []).map((row) => ({
      ...row,
      name: row.User__r?.Name,
      skills: skillList(row.Skills__c).join(', '),
      capacity: row.Weekly_Capacity_Hours__c || this.staffing.defaultCapacity,
      activeText: row.Active__c ? '✓' : ''
    }));
  }

  get hasResources() {
    return this.resources.length > 0;
  }

  get people() {
    return this.candidates.map((row) => ({
      ...row,
      match: helpText('Projects', 'Projects_Staffing_Match', row.matched, row.needed),
      roleText: row.roleMatch ? '✓' : '',
      className: row.allSkills ? 'slds-text-title_bold' : ''
    }));
  }

  get hasCandidates() {
    return this.candidates.length > 0;
  }

  get fillTitle() {
    return this.filling
      ? helpText('Projects', 'Projects_Staffing_FillTitle', this.filling.Role__c)
      : '';
  }

  async load() {
    this.isLoading = true;
    try {
      this.staffing = await getStaffing();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isLoading = false;
    }
  }

  async handleFill(event) {
    const request = this.staffing.requests.find((row) => row.Id === event.target.dataset.id);
    this.isWorking = true;
    try {
      const data = await getAllocation({
        fromDate: request.Start_Date__c,
        toDate: request.End_Date__c
      });
      this.candidates = rankCandidates(request, data);
      this.filling = request;
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }

  handleClose() {
    this.filling = undefined;
    this.candidates = [];
  }

  async handleAssign(event) {
    this.isWorking = true;
    try {
      await fill({ requestId: this.filling.Id, userId: event.target.dataset.user });
      this.notice = helpText('Projects', 'Projects_Staffing_Filled', event.target.dataset.name);
      this.handleClose();
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }

  handleEdit(event) {
    const row = this.staffing.resources.find((item) => item.Id === event.target.dataset.id);
    this.draft = {
      userId: row.User__c,
      skills: skillList(row.Skills__c),
      capacity: row.Weekly_Capacity_Hours__c,
      role: row.Default_Role__c || '',
      active: row.Active__c
    };
  }

  handleNew() {
    this.draft = { ...BLANK };
  }

  handleDraft(event) {
    const field = event.target.dataset.field;
    const value =
      field === 'userId'
        ? event.detail?.recordId
        : field === 'active'
          ? event.target.checked
          : (event.detail?.value ?? event.target.value);
    this.draft = { ...this.draft, [field]: value };
  }

  async handleSave() {
    this.isWorking = true;
    try {
      const d = this.draft;
      await saveResource({
        userId: d.userId,
        skills: (d.skills || []).join(';'),
        weeklyCapacity: d.capacity === '' || d.capacity == null ? null : Number(d.capacity),
        defaultRole: d.role,
        active: d.active
      });
      this.notice = helpText('Projects', 'Projects_Staffing_Saved');
      this.draft = { ...BLANK };
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }
}
