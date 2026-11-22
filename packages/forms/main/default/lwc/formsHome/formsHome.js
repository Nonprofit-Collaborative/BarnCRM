import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { gql, graphql } from 'lightning/graphql';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import FORM_SCHEMA from '@salesforce/schema/Form__c';
import FORM_STATUS_FIELD from '@salesforce/schema/Form__c.Status__c';
import SUBMISSION_SCHEMA from '@salesforce/schema/Form_Submission__c';
import SUBMISSION_STATUS_FIELD from '@salesforce/schema/Form_Submission__c.Status__c';
import SUBMISSION_FORM_NAME_FIELD from '@salesforce/schema/Form_Submission__c.Form_Name__c';
import { iconFor } from 'c/barnIcons';
import { recordHref } from 'c/barnFormat';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const HELP_PACKAGES = ['Forms'];

// Every name comes from a schema import (ADR-0093 A1), so the query works with or without the
// namespace.
const FORM = FORM_SCHEMA.objectApiName;
const SUBMISSION = SUBMISSION_SCHEMA.objectApiName;
const FORM_STATUS = FORM_STATUS_FIELD.fieldApiName;
const SUBMISSION_STATUS = SUBMISSION_STATUS_FIELD.fieldApiName;
const FORM_NAME = SUBMISSION_FORM_NAME_FIELD.fieldApiName;
const RECENT_DAYS = 30;
const DAY_MS = 86400000;

/**
 * The home's figures and lists in one read, as the user, so field security and sharing apply
 * (ADR-0093). Counts are each connection's totalCount; only the recent lists return rows.
 */
const HOME_QUERY = gql`
  query formsHome($since: DateTime) {
    uiapi {
      query {
        forms: ${FORM}(orderBy: { LastModifiedDate: { order: DESC } }, first: 5) {
          totalCount
          edges {
            node {
              Id
              Name {
                value
              }
              ${FORM_STATUS} {
                value
                displayValue
              }
              LastModifiedDate {
                value
              }
            }
          }
        }
        published: ${FORM}(where: { ${FORM_STATUS}: { eq: "Published" } }, first: 1) {
          totalCount
        }
        submissions: ${SUBMISSION}(orderBy: { CreatedDate: { order: DESC } }, first: 10) {
          edges {
            node {
              Id
              Name {
                value
              }
              ${FORM_NAME} {
                value
              }
              ${SUBMISSION_STATUS} {
                value
                displayValue
              }
              CreatedDate {
                value
              }
            }
          }
        }
        received: ${SUBMISSION}(where: { CreatedDate: { gte: { value: $since } } }, first: 1) {
          totalCount
        }
        review: ${SUBMISSION}(
          where: { ${SUBMISSION_STATUS}: { in: ["Needs Review", "Failed"] } }
          first: 1
        ) {
          totalCount
        }
      }
    }
  }
`;

/** A status picklist value as a word of the suite status vocabulary (ux-kit, Visual Standard). */
const STATUS_WORDS = {
  Draft: 'draft',
  Published: 'active',
  Closed: 'closed',
  Received: 'new',
  Processed: 'done',
  'Needs Review': 'review',
  Failed: 'failed'
};

function valueOf(node, field) {
  return node && node[field] ? node[field].value : null;
}

function shownOf(node, field) {
  return node && node[field] ? node[field].displayValue || node[field].value : '';
}

/** Each object's info from a getObjectInfos result, undefined where it was refused. */
function infosOf(results) {
  return results.map((entry) => {
    return entry && entry.statusCode === 200 ? entry.result : undefined;
  });
}

/**
 * Forms Home (ADR-0236, Module Home pattern): published forms, submissions in the last 30 days
 * and submissions that need a look as figures, the forms changed most recently and the newest
 * submissions as lists, and New Form for someone who may create forms. Before the first form, a
 * first-run panel offers New Form instead. Reads only through Lightning Data Service.
 */
export default class FormsHome extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded(HELP_PACKAGES);
  icon = iconFor('Forms_Home');
  isLoading = true;
  errorMessage;
  result;
  formInfo;
  submissionInfo;

  variables = { since: new Date(Date.now() - RECENT_DAYS * DAY_MS).toISOString() };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
  }

  @wire(graphql, { query: HOME_QUERY, variables: '$variables' })
  receiveHome({ data, errors }) {
    if (errors && errors.length) {
      this.errorMessage = helpText('Forms', 'Forms_Home_LoadFailed');
      this.result = undefined;
      this.isLoading = false;
    } else if (data) {
      this.result = data.uiapi.query;
      this.errorMessage = undefined;
      this.isLoading = false;
    }
  }

  @wire(getObjectInfos, { objectApiNames: [FORM_SCHEMA, SUBMISSION_SCHEMA] })
  receiveInfos({ data }) {
    if (data && data.results) {
      const [form, submission] = infosOf(data.results);
      this.formInfo = form;
      this.submissionInfo = submission;
    }
  }

  get labels() {
    return {
      title: helpText('Forms', 'Forms_Home_Title'),
      intro: helpText('Forms', 'Forms_Home_Intro'),
      newForm: helpText('Forms', 'Forms_Home_NewForm'),
      firstRunHeading: helpText('Forms', 'Forms_Home_FirstRunHeading'),
      firstRunMessage: helpText('Forms', 'Forms_Home_FirstRunMessage'),
      published: helpText('Forms', 'Forms_Home_Published'),
      received: helpText('Forms', 'Forms_Home_Received'),
      needReview: helpText('Forms', 'Forms_Home_NeedReview'),
      recentForms: helpText('Forms', 'Forms_Home_RecentForms'),
      noForms: helpText('Forms', 'Forms_Home_NoForms'),
      noFormsNext: helpText('Forms', 'Forms_Home_NoFormsNext'),
      recentSubmissions: helpText('Forms', 'Forms_Home_RecentSubmissions'),
      noSubmissions: helpText('Forms', 'Forms_Home_NoSubmissions'),
      noSubmissionsNext: helpText('Forms', 'Forms_Home_NoSubmissionsNext')
    };
  }

  get canCreate() {
    return Boolean(this.formInfo && this.formInfo.createable);
  }

  get hasResult() {
    return Boolean(this.result);
  }

  get firstRun() {
    return this.hasResult && this.count('forms') === 0;
  }

  get showHome() {
    return this.hasResult && !this.firstRun;
  }

  count(alias) {
    const connection = this.result && this.result[alias];
    return connection && typeof connection.totalCount === 'number' ? connection.totalCount : 0;
  }

  edges(alias) {
    const connection = this.result && this.result[alias];
    return (connection && connection.edges) || [];
  }

  get tiles() {
    const labels = this.labels;
    return [
      {
        key: 'published',
        label: labels.published,
        value: this.count('published'),
        href: listHref(FORM)
      },
      {
        key: 'received',
        label: labels.received,
        value: this.count('received'),
        href: listHref(SUBMISSION)
      },
      {
        key: 'review',
        label: labels.needReview,
        value: this.count('review'),
        href: listHref(SUBMISSION)
      }
    ];
  }

  get sections() {
    const labels = this.labels;
    const formLabels = fieldLabels(this.formInfo);
    const submissionLabels = fieldLabels(this.submissionInfo);
    return [
      {
        key: 'forms',
        heading: labels.recentForms,
        empty: labels.noForms,
        next: labels.noFormsNext,
        columns: [
          { key: 'name', label: formLabels.Name || '' },
          { key: 'status', label: formLabels[FORM_STATUS] || '' },
          { key: 'when', label: formLabels.LastModifiedDate || '' }
        ],
        rows: this.edges('forms').map(({ node }) => ({
          id: node.Id,
          cells: [
            { key: 'name', isLink: true, value: valueOf(node, 'Name'), href: recordHref(node.Id) },
            statusCell(node, FORM_STATUS),
            { key: 'when', isDateTime: true, value: valueOf(node, 'LastModifiedDate') }
          ]
        }))
      },
      {
        key: 'submissions',
        heading: labels.recentSubmissions,
        empty: labels.noSubmissions,
        next: labels.noSubmissionsNext,
        columns: [
          { key: 'name', label: submissionLabels.Name || '' },
          { key: 'form', label: submissionLabels[FORM_NAME] || '' },
          { key: 'status', label: submissionLabels[SUBMISSION_STATUS] || '' },
          { key: 'when', label: submissionLabels.CreatedDate || '' }
        ],
        rows: this.edges('submissions').map(({ node }) => ({
          id: node.Id,
          cells: [
            { key: 'name', isLink: true, value: valueOf(node, 'Name'), href: recordHref(node.Id) },
            { key: 'form', isText: true, value: valueOf(node, FORM_NAME) },
            statusCell(node, SUBMISSION_STATUS),
            { key: 'when', isDateTime: true, value: valueOf(node, 'CreatedDate') }
          ]
        }))
      }
    ].map(finishSection);
  }

  handleNewForm() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: FORM, actionName: 'new' }
    });
  }
}

function listHref(objectApiName) {
  return `/lightning/o/${objectApiName}/list`;
}

function fieldLabels(info) {
  const labels = {};
  const fields = (info && info.fields) || {};
  Object.keys(fields).forEach((name) => {
    labels[name] = fields[name].label;
  });
  return labels;
}

function statusCell(node, field) {
  return {
    key: 'status',
    isStatus: true,
    value: shownOf(node, field),
    status: STATUS_WORDS[valueOf(node, field)] || 'neutral'
  };
}

/** Each cell carries its column label for the stacked phone view. */
function finishSection(section) {
  const labelOf = {};
  section.columns.forEach((column) => {
    labelOf[column.key] = column.label;
  });
  return {
    ...section,
    hasRows: section.rows.length > 0,
    rows: section.rows.map((row) => ({
      ...row,
      cells: row.cells.map((cell) => ({ ...cell, column: labelOf[cell.key] }))
    }))
  };
}
