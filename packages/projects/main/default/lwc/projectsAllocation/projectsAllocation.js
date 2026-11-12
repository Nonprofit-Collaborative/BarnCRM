import { LightningElement } from 'lwc';
import getAllocation from '@salesforce/apex/ProjectStaffingController.getAllocation';
import { localIsoDate, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { allocation, mondayOf, weekRange } from 'c/projectsAllocationModel';

const PKG = 'Projects';
const WEEK_CHOICES = [4, 8, 12, 26];

/**
 * The weekly allocation view (PM-09, R-PM14): each active person's planned hours against their
 * capacity, week by week, with logged hours and unfilled requests as demand. The figures are
 * worked out here by `c/projectsAllocationModel` from what Apex returns.
 */
export default class ProjectsAllocation extends LightningElement {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Project_Resource__c');
  start = mondayOf(localIsoDate());
  weeks = 8;
  view;
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
      title: helpText('Projects', 'Projects_Allocation_Title'),
      intro: helpText('Projects', 'Projects_Allocation_Intro'),
      from: helpText('Projects', 'Projects_Allocation_From'),
      weeks: helpText('Projects', 'Projects_Allocation_Weeks'),
      show: helpText('Projects', 'Projects_Allocation_Show'),
      person: helpText('Projects', 'Projects_Allocation_Person'),
      demand: helpText('Projects', 'Projects_Allocation_Demand'),
      none: helpText('Projects', 'Projects_Allocation_None')
    };
  }

  get weekOptions() {
    return WEEK_CHOICES.map((count) => ({ label: String(count), value: String(count) }));
  }

  get heads() {
    return (this.view?.weeks || []).map((week) => ({ week, label: week.slice(5) }));
  }

  get rows() {
    return (this.view?.people || []).map((person) => ({
      ...person,
      cells: person.cells.map((cell) => ({
        ...cell,
        key: `${person.id}${cell.week}`,
        text: `${cell.allocated} / ${cell.capacity} (${cell.percent}%)`,
        title: helpText('Projects', 'Projects_Allocation_Logged', cell.logged),
        className: cell.over ? 'slds-text-color_error slds-text-title_bold' : ''
      }))
    }));
  }

  get demandCells() {
    return (this.view?.demand || []).map((cell) => ({ ...cell, key: `demand${cell.week}` }));
  }

  get hasPeople() {
    return this.rows.length > 0;
  }

  handleField(event) {
    this[event.target.dataset.field] = event.target.value;
  }

  async load() {
    const range = weekRange(this.start, Number(this.weeks));
    if (!range) {
      return;
    }
    try {
      const data = await getAllocation({ fromDate: range.from, toDate: range.to });
      this.view = allocation(data, range.from, range.to);
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }
}
