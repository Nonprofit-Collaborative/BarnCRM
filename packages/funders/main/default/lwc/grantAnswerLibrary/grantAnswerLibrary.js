import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLibrary from '@salesforce/apex/GrantAnswerController.getLibrary';
import markUsed from '@salesforce/apex/GrantAnswerController.markUsed';
import { filterAnswers, preview, topicList } from 'c/grantAnswerModel';
import { format, messageFrom as messageOf } from 'c/findCsv';
import { showDate } from 'c/grantReportModel';

import TITLE from '@salesforce/label/c.Funders_Answers_Title';
import SEARCH from '@salesforce/label/c.Funders_Answers_Search';
import TOPIC from '@salesforce/label/c.Funders_Answers_Topic';
import ALL_TOPICS from '@salesforce/label/c.Funders_Answers_AllTopics';
import COPY from '@salesforce/label/c.Core_RecordInspector_Copy';
import COPIED from '@salesforce/label/c.Funders_Answers_Copied';
import COPY_FAILED from '@salesforce/label/c.Funders_Answers_CopyFailed';
import SHOW_ALL from '@salesforce/label/c.Funders_Answers_ShowAll';
import SHOW_LESS from '@salesforce/label/c.Funders_Answers_ShowLess';
import WORDS from '@salesforce/label/c.Funders_Answers_Words';
import LAST_USED from '@salesforce/label/c.Funders_Answers_LastUsed';
import NEVER_USED from '@salesforce/label/c.Funders_Answers_NeverUsed';
import NO_MATCH from '@salesforce/label/c.Funders_Answers_NoMatch';
import NEW_ANSWER from '@salesforce/label/c.Funders_Answers_New';
import ERROR_LOAD from '@salesforce/label/c.Funders_Answers_ErrorLoad';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PREVIEW_LENGTH = 240;

/**
 * The Answer Library card on a grant's page (F-14, canonical model 29ZN): search and filter the
 * organization's reusable application answers by topic, and copy one to the clipboard, which
 * stamps its Last Used Date (R-GA3). The search and topics are the framework-free
 * `grantAnswerModel`'s.
 */
export default class GrantAnswerLibrary extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Funders');

  @api recordId;

  labels = {
    title: TITLE,
    search: SEARCH,
    topic: TOPIC,
    newAnswer: NEW_ANSWER,
    get empty() {
      return helpText('Funders', 'Funders_Answers_Empty');
    },
    noMatch: NO_MATCH
  };

  library;
  search = '';
  topic = '';
  expanded = new Set();
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
      this.library = await getLibrary();
      this.errorMessage = undefined;
    } catch (error) {
      this.library = undefined;
      this.errorMessage = messageOf(error, ERROR_LOAD);
    } finally {
      this.isLoading = false;
    }
  }

  get answers() {
    return (this.library && this.library.answers) || [];
  }

  get hasAnswers() {
    return this.answers.length > 0;
  }

  get isEmpty() {
    return Boolean(this.library) && !this.hasAnswers;
  }

  get canCreate() {
    return Boolean(this.library && this.library.canCreate);
  }

  get topicOptions() {
    return [
      { label: ALL_TOPICS, value: '' },
      ...topicList(this.answers).map((topic) => ({ label: topic, value: topic }))
    ];
  }

  get rows() {
    return filterAnswers(this.answers, this.topic, this.search).map((answer) => {
      const open = this.expanded.has(answer.id);
      const long = answer.text.length > PREVIEW_LENGTH;
      return {
        id: answer.id,
        title: answer.title,
        topics: answer.topicList.map((topic, index) => ({ key: `${answer.id}-${index}`, topic })),
        text: open || !long ? answer.text : preview(answer.text, PREVIEW_LENGTH),
        long,
        toggleLabel: open ? SHOW_LESS : SHOW_ALL,
        copyLabel: COPY,
        meta: [
          format(WORDS, answer.words),
          answer.lastUsed ? format(LAST_USED, showDate(answer.lastUsed)) : NEVER_USED
        ].join(' | ')
      };
    });
  }

  get noMatch() {
    return this.hasAnswers && this.rows.length === 0;
  }

  handleSearch(event) {
    this.search = event.detail.value || '';
  }

  handleTopic(event) {
    this.topic = event.detail.value || '';
  }

  handleToggle(event) {
    const { id } = event.currentTarget.dataset;
    const expanded = new Set(this.expanded);
    if (expanded.has(id)) {
      expanded.delete(id);
    } else {
      expanded.add(id);
    }
    this.expanded = expanded;
  }

  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: event.currentTarget.dataset.id,
        objectApiName: 'Grant_Answer__c',
        actionName: 'view'
      }
    });
  }

  handleNew() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Grant_Answer__c', actionName: 'new' }
    });
  }

  async handleCopy(event) {
    const { id } = event.currentTarget.dataset;
    const answer = this.answers.find((each) => each.id === id);
    if (!answer) {
      return;
    }
    try {
      await navigator.clipboard.writeText(answer.text);
    } catch {
      this.toast(COPY_FAILED, 'warning');
      return;
    }
    this.toast(COPIED, 'success');
    try {
      const stamped = await markUsed({ answerId: id });
      if (stamped) {
        const withDate = (each) => (each.id === id ? { ...each, lastUsed: stamped } : each);
        this.library = { ...this.library, answers: this.answers.map(withDate) };
      }
    } catch (error) {
      this.toast(messageOf(error, ERROR_LOAD), 'error');
    }
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
