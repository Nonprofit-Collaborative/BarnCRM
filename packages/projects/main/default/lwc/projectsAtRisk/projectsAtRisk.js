import { LightningElement } from 'lwc';
import getAtRisk from '@salesforce/apex/ProjectsController.getAtRisk';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PKG = 'Projects';

/**
 * The Projects at Risk card (PM-05): Active projects that are At Risk or Off Track, Off Track
 * first, with their reasons and an Only Mine filter. On Projects Home and any Lightning home or
 * app page.
 */
export default class ProjectsAtRisk extends LightningElement {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Project__c');
  rows = [];
  onlyMine = false;
  errorMessage;

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
      title: helpText('Projects', 'Projects_AtRisk_Title'),
      onlyMine: helpText('Projects', 'Projects_AtRisk_OnlyMine'),
      none: helpText('Projects', 'Projects_AtRisk_None')
    };
  }

  get projects() {
    return this.rows.map((row) => ({
      ...row,
      href: `/lightning/r/${row.id}/view`,
      badgeClass:
        row.health === 'Off Track'
          ? 'slds-badge slds-theme_error'
          : 'slds-badge slds-theme_warning',
      reasons: (row.healthReasons || '')
        .split('\n')
        .filter((line) => line)
        .join('; ')
    }));
  }

  get hasProjects() {
    return this.rows.length > 0;
  }

  async load() {
    try {
      this.rows = await getAtRisk({ onlyMine: this.onlyMine });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  handleOnlyMine(event) {
    this.onlyMine = event.target.checked;
    this.load();
  }
}
