import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getDocumentStatus from '@salesforce/apex/CorporateHubController.getDocumentStatus';
import requestAcknowledgments from '@salesforce/apex/CorporateHubController.requestAcknowledgments';
import publishNewVersion from '@salesforce/apex/CorporateHubController.publishNewVersion';
import markReviewed from '@salesforce/apex/CorporateHubController.markReviewed';
import retire from '@salesforce/apex/CorporateHubController.retire';
import acknowledge from '@salesforce/apex/CorporateHubController.acknowledge';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { groupName } from 'c/corporateHubModel';

const HELP_PACKAGES = ['CorporateHub'];
const ACKNOWLEDGED = 'Acknowledged';

/**
 * The library document panel (CH-01, CH-02; R-HD1, R-HD2, R-PAK1 to R-PAK3): the version and
 * who has and has not acknowledged it, the file upload (Salesforce Files on the document), and
 * for a holder of Manage Corporate Hub Publish New Version, Retire, Request Acknowledgments
 * (everyone with a BarnCRM role, or one public group) and Record for a paper attestation. Mark
 * Reviewed needs only edit access.
 */
export default class HubDocumentPanel extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  status;
  group = '';
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

  get labels() {
    return {
      title: helpText('CorporateHub', 'CorporateHub_Document_Title'),
      version: helpText('CorporateHub', 'CorporateHub_Document_Version', this.version),
      counts: helpText(
        'CorporateHub',
        'CorporateHub_Document_Counts',
        this.status ? this.status.acknowledged : 0,
        this.status ? this.status.outstanding : 0
      ),
      upload: helpText('CorporateHub', 'CorporateHub_Document_Upload'),
      publish: helpText('CorporateHub', 'CorporateHub_Document_Publish'),
      reviewed: helpText('CorporateHub', 'CorporateHub_Document_Reviewed'),
      retire: helpText('CorporateHub', 'CorporateHub_Document_Retire'),
      request: helpText('CorporateHub', 'CorporateHub_Document_Request'),
      group: helpText('CorporateHub', 'CorporateHub_Document_Group'),
      record: helpText('CorporateHub', 'CorporateHub_Document_Record')
    };
  }

  async load() {
    try {
      this.status = await getDocumentStatus({ documentId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(
        error,
        helpText('CorporateHub', 'CorporateHub_Error_Generic')
      );
    }
  }

  get version() {
    return this.status && this.status.version != null ? this.status.version : '';
  }

  get canManage() {
    return Boolean(this.status && this.status.canManage);
  }

  get canEdit() {
    return Boolean(this.status && this.status.canEdit);
  }

  get canAsk() {
    return this.canManage && Boolean(this.status.needsAcknowledgment);
  }

  get people() {
    return ((this.status && this.status.people) || []).map((row) => ({
      ...row,
      canRecord: this.canManage && row.status !== ACKNOWLEDGED
    }));
  }

  get hasPeople() {
    return this.people.length > 0;
  }

  handleGroup(event) {
    this.group = event.target.value;
  }

  handleUploaded() {
    notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    this.toast(helpText('CorporateHub', 'CorporateHub_Document_Uploaded'));
  }

  handlePublish() {
    return this.run(
      () => publishNewVersion({ documentId: this.recordId }),
      () => helpText('CorporateHub', 'CorporateHub_Document_Published')
    );
  }

  handleReviewed() {
    return this.run(
      () => markReviewed({ documentId: this.recordId }),
      () => helpText('CorporateHub', 'CorporateHub_Document_ReviewedDone')
    );
  }

  handleRetire() {
    return this.run(
      () => retire({ documentId: this.recordId }),
      () => helpText('CorporateHub', 'CorporateHub_Document_Retired')
    );
  }

  handleRequest() {
    return this.run(
      () => requestAcknowledgments({ documentId: this.recordId, groupName: groupName(this.group) }),
      (asked) => helpText('CorporateHub', 'CorporateHub_Document_Asked', asked || 0)
    );
  }

  handleRecord(event) {
    const acknowledgmentId = event.currentTarget.dataset.rowId;
    return this.run(
      () => acknowledge({ acknowledgmentId }),
      () => helpText('CorporateHub', 'CorporateHub_Home_Acknowledged')
    );
  }

  toast(message) {
    this.dispatchEvent(new ShowToastEvent({ message, variant: 'success' }));
  }

  /** One server call, then a toast and the record and panel refreshed. */
  async run(call, success) {
    this.isWorking = true;
    try {
      const result = await call();
      this.toast(success(result));
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
