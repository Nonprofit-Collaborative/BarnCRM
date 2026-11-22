import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { gql, graphql } from 'lightning/graphql';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import LOCALE from '@salesforce/i18n/locale';
import TERM_SCHEMA from '@salesforce/schema/Membership_Term__c';
import LEVEL_SCHEMA from '@salesforce/schema/Membership_Level__c';
import STATUS_FIELD from '@salesforce/schema/Membership_Term__c.Status__c';
import END_DATE_FIELD from '@salesforce/schema/Membership_Term__c.End_Date__c';
import START_DATE_FIELD from '@salesforce/schema/Membership_Term__c.Start_Date__c';
import MEMBER_NAME_FIELD from '@salesforce/schema/Membership_Term__c.Member_Name__c';
import LEVEL_FIELD from '@salesforce/schema/Membership_Term__c.Level__c';
import PREVIOUS_TERM_FIELD from '@salesforce/schema/Membership_Term__c.Previous_Term__c';
import { iconFor } from 'c/barnIcons';
import { formatDate, isoDate, recordHref } from 'c/barnFormat';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const HELP_PACKAGES = ['Memberships'];

// Every name comes from a schema import (ADR-0093 A1), so the query works with or without the
// namespace.
const TERM = TERM_SCHEMA.objectApiName;
const LEVEL_OBJECT = LEVEL_SCHEMA.objectApiName;
const STATUS = STATUS_FIELD.fieldApiName;
const END_DATE = END_DATE_FIELD.fieldApiName;
const START_DATE = START_DATE_FIELD.fieldApiName;
const MEMBER_NAME = MEMBER_NAME_FIELD.fieldApiName;
const LEVEL = LEVEL_FIELD.fieldApiName;
const LEVEL_PARENT = LEVEL.replace(/__c$/, '__r');
const PREVIOUS_TERM = PREVIOUS_TERM_FIELD.fieldApiName;
const WINDOW_DAYS = 30;
const DAY_MS = 86400000;

const TERM_NODE = `
  Id
  Name {
    value
  }
  ${MEMBER_NAME} {
    value
  }
  ${LEVEL_PARENT} {
    Name {
      value
    }
  }
  ${STATUS} {
    value
    displayValue
  }
`;

/**
 * The home's figures and lists in one read, as the user, so field security and sharing apply
 * (ADR-0093). Active is Current or Grace, the statuses the term's Is Active formula counts.
 * Expiring is a Current term ending in the next 30 days; a renewal is a term that follows an
 * earlier one, created in the last 30 days.
 */
const HOME_QUERY = gql`
  query membershipsHome($today: Date, $soon: Date, $since: DateTime) {
    uiapi {
      query {
        terms: ${TERM}(first: 1) {
          totalCount
        }
        levels: ${LEVEL_OBJECT}(first: 1) {
          totalCount
        }
        active: ${TERM}(where: { ${STATUS}: { in: ["Current", "Grace"] } }, first: 1) {
          totalCount
        }
        grace: ${TERM}(where: { ${STATUS}: { eq: "Grace" } }, first: 1) {
          totalCount
        }
        expiring: ${TERM}(
          where: {
            and: [
              { ${STATUS}: { eq: "Current" } }
              { ${END_DATE}: { gte: { value: $today } } }
              { ${END_DATE}: { lte: { value: $soon } } }
            ]
          }
          orderBy: { ${END_DATE}: { order: ASC } }
          first: 10
        ) {
          totalCount
          edges {
            node {
              ${TERM_NODE}
              ${END_DATE} {
                value
              }
            }
          }
        }
        renewals: ${TERM}(
          where: {
            and: [{ ${PREVIOUS_TERM}: { ne: null } }, { CreatedDate: { gte: { value: $since } } }]
          }
          orderBy: { CreatedDate: { order: DESC } }
          first: 10
        ) {
          totalCount
          edges {
            node {
              ${TERM_NODE}
              ${START_DATE} {
                value
              }
            }
          }
        }
      }
    }
  }
`;

/** A term status as a word of the suite status vocabulary (ux-kit, Visual Standard). */
const STATUS_WORDS = {
  Pending: 'pending',
  Current: 'current',
  Grace: 'due soon',
  Lapsed: 'expired',
  Renewed: 'done',
  Cancelled: 'inactive'
};

function valueOf(node, field) {
  return node && node[field] ? node[field].value : null;
}

/** Each object's info from a getObjectInfos result, undefined where it was refused. */
function infosOf(results) {
  return results.map((entry) => {
    return entry && entry.statusCode === 200 ? entry.result : undefined;
  });
}

function variablesFor(now) {
  return {
    today: isoDate(now),
    soon: isoDate(new Date(now.getTime() + WINDOW_DAYS * DAY_MS)),
    since: new Date(now.getTime() - WINDOW_DAYS * DAY_MS).toISOString()
  };
}

/**
 * Memberships Home (ADR-NEXT, Module Home pattern): active members, terms expiring in the next 30
 * days, members in their grace period and renewals in the last 30 days as figures; the terms
 * expiring soonest and the newest renewals as lists; and New Membership for someone who may
 * create one. Before the first membership a first-run panel points to the next step: a level
 * first when there is none. Reads only through Lightning Data Service.
 */
export default class MembershipsHome extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded(HELP_PACKAGES);
  icon = iconFor('Memberships_Home');
  isLoading = true;
  errorMessage;
  result;
  termInfo;
  levelInfo;

  variables = variablesFor(new Date());

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
      this.errorMessage = helpText('Memberships', 'Memberships_Home_LoadFailed');
      this.result = undefined;
      this.isLoading = false;
    } else if (data) {
      this.result = data.uiapi.query;
      this.errorMessage = undefined;
      this.isLoading = false;
    }
  }

  @wire(getObjectInfos, { objectApiNames: [TERM_SCHEMA, LEVEL_SCHEMA] })
  receiveInfos({ data }) {
    if (data && data.results) {
      const [term, level] = infosOf(data.results);
      this.termInfo = term;
      this.levelInfo = level;
    }
  }

  get labels() {
    return {
      title: helpText('Memberships', 'Memberships_Home_Title'),
      intro: helpText('Memberships', 'Memberships_Home_Intro'),
      newMembership: helpText('Memberships', 'Memberships_Home_NewMembership'),
      newLevel: helpText('Memberships', 'Memberships_Home_NewLevel'),
      active: helpText('Memberships', 'Memberships_Home_Active'),
      expiring: helpText('Memberships', 'Memberships_Home_Expiring'),
      grace: helpText('Memberships', 'Memberships_Home_Grace'),
      renewals: helpText('Memberships', 'Memberships_Home_Renewals'),
      expiringList: helpText('Memberships', 'Memberships_Home_ExpiringList'),
      noExpiring: helpText('Memberships', 'Memberships_Home_NoExpiring'),
      noExpiringNext: helpText('Memberships', 'Memberships_Home_NoExpiringNext'),
      renewalsList: helpText('Memberships', 'Memberships_Home_RenewalsList'),
      noRenewals: helpText('Memberships', 'Memberships_Home_NoRenewals'),
      noRenewalsNext: helpText('Memberships', 'Memberships_Home_NoRenewalsNext'),
      levelFirstHeading: helpText('Memberships', 'Memberships_Home_LevelFirstHeading'),
      levelFirstMessage: helpText('Memberships', 'Memberships_Home_LevelFirstMessage'),
      memberFirstHeading: helpText('Memberships', 'Memberships_Home_MemberFirstHeading'),
      memberFirstMessage: helpText('Memberships', 'Memberships_Home_MemberFirstMessage')
    };
  }

  get canCreate() {
    return Boolean(this.termInfo && this.termInfo.createable);
  }

  get canCreateLevel() {
    return Boolean(this.levelInfo && this.levelInfo.createable);
  }

  get firstRun() {
    return Boolean(this.result) && this.count('terms') === 0;
  }

  /** Before the first level, the first step is a level; after it, a membership. */
  get needsLevel() {
    return this.firstRun && this.count('levels') === 0;
  }

  get firstRunHeading() {
    return this.needsLevel ? this.labels.levelFirstHeading : this.labels.memberFirstHeading;
  }

  get firstRunMessage() {
    return this.needsLevel ? this.labels.levelFirstMessage : this.labels.memberFirstMessage;
  }

  get showFirstRunLevel() {
    return this.needsLevel && this.canCreateLevel;
  }

  get showFirstRunMember() {
    return this.firstRun && !this.needsLevel && this.canCreate;
  }

  get showHome() {
    return Boolean(this.result) && !this.firstRun;
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
    const list = `/lightning/o/${TERM}/list`;
    return [
      { key: 'active', label: labels.active, value: this.count('active'), href: list },
      { key: 'expiring', label: labels.expiring, value: this.count('expiring'), href: list },
      { key: 'grace', label: labels.grace, value: this.count('grace'), href: list },
      { key: 'renewals', label: labels.renewals, value: this.count('renewals'), href: list }
    ];
  }

  get sections() {
    const labels = this.labels;
    const fields = (this.termInfo && this.termInfo.fields) || {};
    const label = (name) => (fields[name] ? fields[name].label : '');
    const columns = (dateField) => [
      { key: 'name', label: label('Name') },
      { key: 'member', label: label(MEMBER_NAME) },
      { key: 'level', label: label(LEVEL) },
      { key: 'date', label: label(dateField) },
      { key: 'status', label: label(STATUS) }
    ];
    const rows = (alias, dateField) =>
      this.edges(alias).map(({ node }) => ({
        id: node.Id,
        cells: [
          { key: 'name', isLink: true, value: valueOf(node, 'Name'), href: recordHref(node.Id) },
          { key: 'member', value: valueOf(node, MEMBER_NAME) },
          { key: 'level', value: node[LEVEL_PARENT] ? valueOf(node[LEVEL_PARENT], 'Name') : '' },
          { key: 'date', value: formatDate(valueOf(node, dateField), LOCALE) },
          {
            key: 'status',
            isStatus: true,
            value: node[STATUS] ? node[STATUS].displayValue || node[STATUS].value : '',
            status: STATUS_WORDS[valueOf(node, STATUS)] || 'neutral'
          }
        ]
      }));
    return [
      {
        key: 'expiring-list',
        heading: labels.expiringList,
        empty: labels.noExpiring,
        next: labels.noExpiringNext,
        columns: columns(END_DATE),
        rows: rows('expiring', END_DATE)
      },
      {
        key: 'renewals-list',
        heading: labels.renewalsList,
        empty: labels.noRenewals,
        next: labels.noRenewalsNext,
        columns: columns(START_DATE),
        rows: rows('renewals', START_DATE)
      }
    ].map(finishSection);
  }

  handleNewMembership() {
    this.openNew(TERM);
  }

  handleNewLevel() {
    this.openNew(LEVEL_OBJECT);
  }

  openNew(objectApiName) {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName, actionName: 'new' }
    });
  }
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
