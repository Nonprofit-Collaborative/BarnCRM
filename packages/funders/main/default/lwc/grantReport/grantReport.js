import { LightningElement, api } from 'lwc';
import getReportData from '@salesforce/apex/GrantReportController.getReportData';
import { fileName, messageFrom as messageOf, saveBlob } from 'c/findCsv';
import { mergeReport, reportDocument } from 'c/grantReportModel';

import TITLE from '@salesforce/label/c.Funders_Report_Title';
import TEMPLATE from '@salesforce/label/c.Core_Import_StepTemplate';
import DOWNLOAD from '@salesforce/label/c.Funders_Report_Download';
import NO_TEMPLATES from '@salesforce/label/c.Funders_Report_NoTemplates';
import DOWNLOADED from '@salesforce/label/c.Core_Shared_ReportDownloaded';
import ERROR_LOAD from '@salesforce/label/c.Funders_Report_ErrorLoad';
import PERIOD_LINE from '@salesforce/label/c.Funders_Outcomes_PeriodLine';
import NOT_SET from '@salesforce/label/c.Funders_Outcomes_NotSet';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const FILE_BASE = 'Funder_Report';

/**
 * The Funder Report card on a grant's page (F-06, canonical model 29ZO): choose a template and
 * download the grant merged into it as a printable HTML file. The merge is the framework-free
 * `grantReportModel`'s (R-FT2); nothing is saved in the org.
 */
export default class GrantReport extends LightningElement {
  helpReady = isHelpLoaded('Funders');

  @api recordId;

  labels = {
    title: TITLE,
    template: TEMPLATE,
    download: DOWNLOAD,
    get help() {
      return helpText('Funders', 'Funders_Report_Help');
    },
    noTemplates: NO_TEMPLATES
  };

  data;
  templateId;
  resultMessage;
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
      this.data = await getReportData({ grantId: this.recordId });
      const templates = this.data.templates || [];
      this.templateId = templates.length > 0 ? templates[0].id : undefined;
      this.errorMessage = undefined;
    } catch (error) {
      this.data = undefined;
      this.errorMessage = messageOf(error, ERROR_LOAD);
    } finally {
      this.isLoading = false;
    }
  }

  get templates() {
    return (this.data && this.data.templates) || [];
  }

  get hasTemplates() {
    return this.templates.length > 0;
  }

  get noTemplates() {
    return Boolean(this.data) && !this.hasTemplates;
  }

  get options() {
    return this.templates.map((template) => ({ label: template.name, value: template.id }));
  }

  handleTemplate(event) {
    this.templateId = event.detail.value;
  }

  handleDownload() {
    const template = this.templates.find((each) => each.id === this.templateId);
    if (!template) {
      return;
    }
    const body = mergeReport(template.body, this.data, {
      periodLine: PERIOD_LINE,
      notSet: NOT_SET
    });
    const grantName = (this.data.grant && this.data.grant.GrantName) || '';
    const html = reportDocument(`${template.name}: ${grantName}`, body);
    saveBlob(
      new Blob([html], { type: 'text/html;charset=utf-8' }),
      fileName(FILE_BASE, new Date(), 'html')
    );
    this.resultMessage = DOWNLOADED;
  }
}
