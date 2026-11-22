import { LightningElement, wire } from 'lwc';
import { gql, graphql } from 'lightning/graphql';
import USER_ID from '@salesforce/user/Id';
import PROJECT from '@salesforce/schema/Project__c';
import STATUS_FIELD from '@salesforce/schema/Project__c.Status__c';
import TEMPLATE_FIELD from '@salesforce/schema/Project__c.Is_Template__c';
import HEALTH_FIELD from '@salesforce/schema/Project__c.Health__c';
import REASONS_FIELD from '@salesforce/schema/Project__c.Health_Reasons__c';
import TARGET_DATE_FIELD from '@salesforce/schema/Project__c.Target_Date__c';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PKG = 'Projects';
const OFF_TRACK = 'Off Track';

// Every name comes from a schema import (ADR-0093 A1), so the query works with any namespace.
const PROJECT_OBJECT = PROJECT.objectApiName;
const HEALTH = HEALTH_FIELD.fieldApiName;
const REASONS = REASONS_FIELD.fieldApiName;

/**
 * Active projects (not templates) that are At Risk or Off Track, read as the user (ADR-0093 A2),
 * by Target Date with undated ones last. The card puts Off Track first.
 */
const AT_RISK_QUERY = gql`
  query projectsAtRisk {
    uiapi {
      query {
        ${PROJECT_OBJECT}(
          where: {
            ${STATUS_FIELD.fieldApiName}: { eq: "Active" }
            ${TEMPLATE_FIELD.fieldApiName}: { eq: false }
            ${HEALTH}: { in: ["At Risk", "Off Track"] }
          }
          orderBy: { ${TARGET_DATE_FIELD.fieldApiName}: { order: ASC, nulls: LAST } }
          first: 200
        ) {
          edges {
            node {
              Id
              Name {
                value
              }
              ${HEALTH} {
                value
              }
              ${REASONS} {
                value
              }
              OwnerId {
                value
              }
              Owner {
                ... on User {
                  Name {
                    value
                  }
                }
              }
            }
          }
        }
      }
    }
  }
`;

/** One project node as the card's row. */
function toRow(node) {
  return {
    id: node.Id,
    name: node.Name.value,
    health: node[HEALTH] ? node[HEALTH].value : null,
    healthReasons: node[REASONS] ? node[REASONS].value : null,
    ownerId: node.OwnerId ? node.OwnerId.value : null,
    ownerName: node.Owner && node.Owner.Name ? node.Owner.Name.value : ''
  };
}

/**
 * The Projects at Risk card (PM-05): Active projects that are At Risk or Off Track, Off Track
 * first, with their reasons and an Only Mine filter. On Projects Home and any Lightning home or
 * app page.
 */
export default class ProjectsAtRisk extends LightningElement {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Project__c');
  allRows = [];
  onlyMine = false;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
  }

  @wire(graphql, { query: AT_RISK_QUERY })
  receiveProjects({ data, errors }) {
    if (errors && errors.length) {
      this.allRows = [];
      this.errorMessage = helpText('Projects', 'Projects_Error_Generic');
    } else if (data) {
      const rows = data.uiapi.query[PROJECT_OBJECT].edges.map((edge) => toRow(edge.node));
      // Off Track first; the sort is stable, so each group keeps the query's Target Date order.
      rows.sort((a, b) => Number(b.health === OFF_TRACK) - Number(a.health === OFF_TRACK));
      this.allRows = rows;
      this.errorMessage = undefined;
    }
  }

  get labels() {
    return {
      title: helpText('Projects', 'Projects_AtRisk_Title'),
      onlyMine: helpText('Projects', 'Projects_AtRisk_OnlyMine'),
      none: helpText('Projects', 'Projects_AtRisk_None')
    };
  }

  get rows() {
    return this.onlyMine ? this.allRows.filter((row) => row.ownerId === USER_ID) : this.allRows;
  }

  get projects() {
    return this.rows.map((row) => ({
      ...row,
      href: `/lightning/r/${row.id}/view`,
      badgeClass:
        row.health === OFF_TRACK ? 'slds-badge slds-theme_error' : 'slds-badge slds-theme_warning',
      reasons: (row.healthReasons || '')
        .split('\n')
        .filter((line) => line)
        .join('; ')
    }));
  }

  get hasProjects() {
    return this.rows.length > 0;
  }

  handleOnlyMine(event) {
    this.onlyMine = event.target.checked;
  }
}
