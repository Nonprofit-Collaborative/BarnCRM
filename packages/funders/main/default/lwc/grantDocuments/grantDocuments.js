import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import getDocuments from '@salesforce/apex/GrantManagementController.getDocuments';
import REQUIREMENT from '@salesforce/schema/Grant_Requirement__c';
import GRANT_FIELD from '@salesforce/schema/Grant_Requirement__c.Grant__c';
import TYPE_FIELD from '@salesforce/schema/Grant_Requirement__c.Type__c';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/**
 * The Documents card on a grant's page (F-11, canonical model R-GQ8): the letter of inquiry,
 * application and report requirements, each with its latest Salesforce File and that file's
 * version. Uploading a new version of the same file keeps the history in Files.
 */
export default class GrantDocuments extends NavigationMixin(LightningElement) {
  @api recordId;

  helpReady = isHelpLoaded('Funders');
  icon = iconFor('Grant_Requirement__c');
  card;
  errorMessage;
  isLoading = true;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Funders').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.card = await getDocuments({ grantId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.card = undefined;
      this.errorMessage = messageFrom(error, helpText('Funders', 'Funders_Manage_LoadFailed'));
    } finally {
      this.isLoading = false;
    }
  }

  get t() {
    return this.helpReady
      ? {
          title: helpText('Funders', 'Funders_Documents_Title'),
          empty: helpText('Funders', 'Funders_Documents_Empty'),
          add: helpText('Funders', 'Funders_Documents_New'),
          upload: helpText('Funders', 'Funders_Documents_Upload'),
          noFile: helpText('Funders', 'Funders_Documents_NoFile'),
          due: helpText('Funders', 'Funders_Manage_Due')
        }
      : {};
  }

  get documents() {
    const canUpload = Boolean(this.card && this.card.canUpload);
    return ((this.card && this.card.documents) || []).map((document) => ({
      ...document,
      url: `/${document.id}`,
      canUpload,
      version:
        document.fileId && this.helpReady
          ? helpText(
              'Funders',
              'Funders_Documents_Version',
              document.fileVersion,
              document.fileCount
            )
          : ''
    }));
  }

  get hasDocuments() {
    return this.documents.length > 0;
  }

  get canCreate() {
    return Boolean(this.card && this.card.canCreate);
  }

  handleNew() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: REQUIREMENT.objectApiName, actionName: 'new' },
      state: {
        defaultFieldValues: encodeDefaultFieldValues({
          [GRANT_FIELD.fieldApiName]: this.recordId,
          [TYPE_FIELD.fieldApiName]: 'Application'
        })
      }
    });
  }

  handleOpenFile(event) {
    this[NavigationMixin.Navigate]({
      type: 'standard__namedPage',
      attributes: { pageName: 'filePreview' },
      state: { selectedRecordId: event.currentTarget.dataset.file }
    });
  }

  handleUploaded() {
    this.load();
  }
}
