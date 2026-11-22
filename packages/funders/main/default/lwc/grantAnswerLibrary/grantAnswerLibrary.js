import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { gql, graphql } from 'lightning/graphql';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { updateRecord } from 'lightning/uiRecordApi';
import ANSWER from '@salesforce/schema/Grant_Answer__c';
import TOPICS_FIELD from '@salesforce/schema/Grant_Answer__c.Topics__c';
import ANSWER_FIELD from '@salesforce/schema/Grant_Answer__c.Answer__c';
import LAST_USED_FIELD from '@salesforce/schema/Grant_Answer__c.Last_Used_Date__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { filterAnswers, preview, topicList } from 'c/grantAnswerModel';
import { format, localIsoDate, messageFrom } from 'c/findCsv';
import { showDate } from 'c/grantReportModel';

import TITLE from '@salesforce/label/c.Funders_Answers_Title';
import SEARCH from '@salesforce/label/c.Funders_Answers_Search';
import TOPIC from '@salesforce/label/c.Funders_Answers_Topic';
import ALL_TOPICS from '@salesforce/label/c.Funders_Answers_AllTopics';
import COPY from '@salesforce/label/c.Core_RecordInspector_Copy';
import SHOW_ALL from '@salesforce/label/c.Funders_Answers_ShowAll';
import SHOW_LESS from '@salesforce/label/c.Funders_Answers_ShowLess';
import WORDS from '@salesforce/label/c.Funders_Answers_Words';
import LAST_USED from '@salesforce/label/c.Funders_Answers_LastUsed';
import NEVER_USED from '@salesforce/label/c.Funders_Answers_NeverUsed';
import NO_ANSWERS from '@salesforce/label/c.Funders_Answers_NoAnswers';
import NEW_ANSWER from '@salesforce/label/c.Funders_Answers_New';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PREVIEW_LENGTH = 240;
const ANSWER_LIMIT = 500;
const ANSWER_OBJECT = ANSWER.objectApiName;
const TOPICS = TOPICS_FIELD.fieldApiName;
const TEXT = ANSWER_FIELD.fieldApiName;
const LAST_USED_NAME = LAST_USED_FIELD.fieldApiName;

/**
 * The answers by title (R-GA1), read as the person (ADR-0093 A2), names from schema imports
 * (A1). Answer is long text, which a query cannot filter on, so blank ones are left out here.
 */
const LIBRARY_QUERY = gql`
  query grantAnswers {
    uiapi {
      query {
        ${ANSWER_OBJECT}(orderBy: { Name: { order: ASC } }, first: ${ANSWER_LIMIT}) {
          edges {
            node {
              Id
              Name {
                value
              }
              ${TOPICS} {
                value
              }
              ${TEXT} {
                value
              }
              ${LAST_USED_NAME} {
                value
              }
            }
          }
        }
      }
    }
  }
`;

const valueOf = (node, name) => (node[name] ? node[name].value : null);

/** The answers with text, as the card draws them. */
function answersOf(data) {
  return data.uiapi.query[ANSWER_OBJECT].edges
    .map(({ node }) => ({
      id: node.Id,
      title: valueOf(node, 'Name'),
      topics: valueOf(node, TOPICS),
      text: valueOf(node, TEXT),
      lastUsed: valueOf(node, LAST_USED_NAME)
    }))
    .filter((answer) => answer.text && answer.text.trim());
}

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
    get noMatch() {
      return helpText('Funders', 'Funders_Answers_NoMatch');
    },
    noAnswers: NO_ANSWERS
  };

  library;
  search = '';
  topic = '';
  expanded = new Set();
  errorMessage;
  isLoading = true;
  /** Whether the person may add answers, and may stamp Last Used Date, from the object info. */
  canCreate = false;
  canStamp = false;

  refreshLibrary;

  connectedCallback() {
    // A card opened again shows the cached read at once; read it again for new answers.
    if (this.refreshLibrary) {
      this.refreshLibrary();
    }
    if (!this.helpReady) {
      loadHelp('Funders').then(() => {
        this.helpReady = true;
      });
    }
  }

  @wire(graphql, { query: LIBRARY_QUERY })
  receiveLibrary(result) {
    const { data, errors } = result;
    this.refreshLibrary = result.refresh;
    if (errors && errors.length) {
      this.library = undefined;
      this.errorMessage = helpText('Funders', 'Funders_Answers_ErrorLoad');
      this.isLoading = false;
    } else if (data) {
      this.library = { answers: answersOf(data) };
      this.errorMessage = undefined;
      this.isLoading = false;
    }
  }

  @wire(getObjectInfo, { objectApiName: ANSWER })
  receiveInfo({ data }) {
    if (data) {
      const lastUsed = data.fields && data.fields[LAST_USED_NAME];
      this.canCreate = data.createable === true;
      this.canStamp = Boolean(lastUsed && lastUsed.updateable);
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
        objectApiName: ANSWER.objectApiName,
        actionName: 'view'
      }
    });
  }

  handleNew() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: ANSWER.objectApiName, actionName: 'new' }
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
      this.toast(helpText('Funders', 'Funders_Answers_CopyFailed'), 'warning');
      return;
    }
    this.toast(helpText('Funders', 'Funders_Answers_Copied'), 'success');
    // R-GA3: stamp Last Used Date with today, as the person, when they may edit it.
    if (!this.canStamp) {
      return;
    }
    const stamped = localIsoDate();
    try {
      await updateRecord({ fields: { Id: id, [LAST_USED_NAME]: stamped } });
      const withDate = (each) => (each.id === id ? { ...each, lastUsed: stamped } : each);
      this.library = { ...this.library, answers: this.answers.map(withDate) };
    } catch (error) {
      this.toast(messageFrom(error, helpText('Funders', 'Funders_Answers_ErrorStamp')), 'error');
    }
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
