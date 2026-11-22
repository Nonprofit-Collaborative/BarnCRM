import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { gql, graphql } from 'lightning/graphql';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import PORTAL_SCHEMA from '@salesforce/schema/Portal__c';
import PORTAL_STATUS_FIELD from '@salesforce/schema/Portal__c.Status__c';
import ACCESS_MODE_FIELD from '@salesforce/schema/Portal__c.Access_Mode__c';
import ACCESS_SCHEMA from '@salesforce/schema/Portal_Access__c';
import ACCESS_STATUS_FIELD from '@salesforce/schema/Portal_Access__c.Status__c';
import PERSON_FIELD from '@salesforce/schema/Portal_Access__c.Person__c';
import ACCESS_PORTAL_FIELD from '@salesforce/schema/Portal_Access__c.Portal__c';
import LAST_SIGN_IN_FIELD from '@salesforce/schema/Portal_Access__c.Last_Sign_In__c';
import { iconFor } from 'c/barnIcons';
import { recordHref } from 'c/barnFormat';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const HELP_PACKAGES = ['Portal'];

// Every name comes from a schema import (ADR-0093 A1), so the query works with or without the
// namespace.
const PORTAL = PORTAL_SCHEMA.objectApiName;
const ACCESS = ACCESS_SCHEMA.objectApiName;
const PORTAL_STATUS = PORTAL_STATUS_FIELD.fieldApiName;
const ACCESS_MODE = ACCESS_MODE_FIELD.fieldApiName;
const ACCESS_STATUS = ACCESS_STATUS_FIELD.fieldApiName;
const PERSON = PERSON_FIELD.fieldApiName;
const ACCESS_PORTAL = ACCESS_PORTAL_FIELD.fieldApiName;
const LAST_SIGN_IN = LAST_SIGN_IN_FIELD.fieldApiName;
const parentOf = (fieldApiName) => fieldApiName.replace(/__c$/, '__r');
const RECENT_DAYS = 30;
const DAY_MS = 86400000;

/**
 * The home's figures and lists in one read, as the user, so field security and sharing apply
 * (ADR-0093). Counts are each connection's totalCount. No sign-in code, token or authenticator
 * field is read.
 */
const HOME_QUERY = gql`
  query portalBuilderHome($since: DateTime) {
    uiapi {
      query {
        portals: ${PORTAL}(orderBy: { Name: { order: ASC } }, first: 50) {
          totalCount
          edges {
            node {
              Id
              Name {
                value
              }
              ${PORTAL_STATUS} {
                value
                displayValue
              }
              ${ACCESS_MODE} {
                value
                displayValue
              }
            }
          }
        }
        live: ${PORTAL}(where: { ${PORTAL_STATUS}: { eq: "Active" } }, first: 1) {
          totalCount
        }
        access: ${ACCESS}(where: { ${ACCESS_STATUS}: { eq: "Active" } }, first: 1) {
          totalCount
        }
        suspended: ${ACCESS}(where: { ${ACCESS_STATUS}: { eq: "Suspended" } }, first: 1) {
          totalCount
        }
        signIns: ${ACCESS}(
          where: { ${LAST_SIGN_IN}: { gte: { value: $since } } }
          orderBy: { ${LAST_SIGN_IN}: { order: DESC } }
          first: 10
        ) {
          totalCount
          edges {
            node {
              Id
              Name {
                value
              }
              ${parentOf(PERSON)} {
                Name {
                  value
                }
              }
              ${parentOf(ACCESS_PORTAL)} {
                Name {
                  value
                }
              }
              ${LAST_SIGN_IN} {
                value
              }
            }
          }
        }
      }
    }
  }
`;

const STATUS_WORDS = { Active: 'active', Inactive: 'inactive' };

function valueOf(node, field) {
  return node && node[field] ? node[field].value : null;
}

function shownOf(node, field) {
  return node && node[field] ? node[field].displayValue || node[field].value : '';
}

/** The Name of the record a lookup points to, read through its relationship. */
function nameOf(node, field) {
  const parent = node && node[parentOf(field)];
  return parent ? valueOf(parent, 'Name') : '';
}

/** Each object's info from a getObjectInfos result, undefined where it was refused. */
function infosOf(results) {
  return results.map((entry) => {
    return entry && entry.statusCode === 200 ? entry.result : undefined;
  });
}

/**
 * Portal Builder Home (ADR-NEXT, Module Home pattern): active portals, people with access,
 * suspended access and sign-ins in the last 30 days as figures; every portal with its status and
 * access mode, and the latest sign-ins, as lists; and New Portal. Before the first portal a
 * first-run panel offers New Portal instead. Reads only through Lightning Data Service.
 */
export default class PortalBuilderHome extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded(HELP_PACKAGES);
  icon = iconFor('Portal_Builder_Home');
  isLoading = true;
  errorMessage;
  result;
  portalInfo;
  accessInfo;

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
      this.errorMessage = helpText('Portal', 'Portal_Home_LoadFailed');
      this.result = undefined;
      this.isLoading = false;
    } else if (data) {
      this.result = data.uiapi.query;
      this.errorMessage = undefined;
      this.isLoading = false;
    }
  }

  @wire(getObjectInfos, { objectApiNames: [PORTAL_SCHEMA, ACCESS_SCHEMA] })
  receiveInfos({ data }) {
    if (data && data.results) {
      const [portal, access] = infosOf(data.results);
      this.portalInfo = portal;
      this.accessInfo = access;
    }
  }

  get labels() {
    return {
      title: helpText('Portal', 'Portal_Home_Title'),
      intro: helpText('Portal', 'Portal_Home_Intro'),
      newPortal: helpText('Portal', 'Portal_Home_NewPortal'),
      firstRunHeading: helpText('Portal', 'Portal_Home_FirstRunHeading'),
      firstRunMessage: helpText('Portal', 'Portal_Home_FirstRunMessage'),
      live: helpText('Portal', 'Portal_Home_Live'),
      access: helpText('Portal', 'Portal_Home_Access'),
      suspended: helpText('Portal', 'Portal_Home_Suspended'),
      signIns: helpText('Portal', 'Portal_Home_SignIns'),
      portals: helpText('Portal', 'Portal_Home_Portals'),
      recentSignIns: helpText('Portal', 'Portal_Home_RecentSignIns'),
      noSignIns: helpText('Portal', 'Portal_Home_NoSignIns'),
      noSignInsNext: helpText('Portal', 'Portal_Home_NoSignInsNext')
    };
  }

  get canCreate() {
    return Boolean(this.portalInfo && this.portalInfo.createable);
  }

  get firstRun() {
    return Boolean(this.result) && this.count('portals') === 0;
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
    const portals = `/lightning/o/${PORTAL}/list`;
    const access = `/lightning/o/${ACCESS}/list`;
    return [
      { key: 'live', label: labels.live, value: this.count('live'), href: portals },
      { key: 'access', label: labels.access, value: this.count('access'), href: access },
      { key: 'suspended', label: labels.suspended, value: this.count('suspended'), href: access },
      { key: 'sign-ins', label: labels.signIns, value: this.count('signIns'), href: access }
    ];
  }

  get sections() {
    const labels = this.labels;
    const portalFields = (this.portalInfo && this.portalInfo.fields) || {};
    const accessFields = (this.accessInfo && this.accessInfo.fields) || {};
    const label = (fields, name) => (fields[name] ? fields[name].label : '');
    return [
      {
        key: 'portals',
        heading: labels.portals,
        columns: [
          { key: 'name', label: label(portalFields, 'Name') },
          { key: 'status', label: label(portalFields, PORTAL_STATUS) },
          { key: 'mode', label: label(portalFields, ACCESS_MODE) }
        ],
        rows: this.edges('portals').map(({ node }) => ({
          id: node.Id,
          cells: [
            { key: 'name', isLink: true, value: valueOf(node, 'Name'), href: recordHref(node.Id) },
            {
              key: 'status',
              isStatus: true,
              value: shownOf(node, PORTAL_STATUS),
              status: STATUS_WORDS[valueOf(node, PORTAL_STATUS)] || 'neutral'
            },
            { key: 'mode', value: shownOf(node, ACCESS_MODE) }
          ]
        }))
      },
      {
        key: 'sign-in-list',
        heading: labels.recentSignIns,
        empty: labels.noSignIns,
        next: labels.noSignInsNext,
        columns: [
          { key: 'person', label: label(accessFields, PERSON) },
          { key: 'portal', label: label(accessFields, ACCESS_PORTAL) },
          { key: 'when', label: label(accessFields, LAST_SIGN_IN) }
        ],
        rows: this.edges('signIns').map(({ node }) => ({
          id: node.Id,
          cells: [
            {
              key: 'person',
              isLink: true,
              value: nameOf(node, PERSON) || valueOf(node, 'Name'),
              href: recordHref(node.Id)
            },
            { key: 'portal', value: nameOf(node, ACCESS_PORTAL) },
            { key: 'when', isDateTime: true, value: valueOf(node, LAST_SIGN_IN) }
          ]
        }))
      }
    ].map(finishSection);
  }

  handleNewPortal() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: PORTAL, actionName: 'new' }
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
