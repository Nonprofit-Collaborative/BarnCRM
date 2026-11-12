import { LightningElement, api } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBudget from '@salesforce/apex/EventBudgetController.getBudget';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import EventRecordModal from 'c/eventRecordModal';
import BarnConfirmModal from 'c/barnConfirmModal';
import { expenseTotals, fundingTotals, netCosts } from 'c/eventBudgetModel';

import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';

const HELP_PACKAGES = ['Events'];
const EXPENSE_FIELDS = [
  'Name',
  'Category__c',
  'Budgeted__c',
  'Actual__c',
  'Vendor__c',
  'Status__c',
  'Due_Date__c'
];
const FUNDING_FIELDS = [
  'Name',
  'Type__c',
  'Account__c',
  'Event_Sponsor__c',
  'Expected__c',
  'Received__c'
];

function money(value) {
  return Number(value || 0).toLocaleString(undefined, { maximumFractionDigits: 2 });
}

/**
 * The Budget panel on the event page's Details tab (EV-23): expense lines with budgeted and
 * actual by category, funding from sponsors and partners, and Net Cost (R-EXP1). Lines are added
 * and changed through the record form and removed through the record API, so the person's own
 * access decides; Events Read Only see the panel with no buttons or menus.
 */
export default class EventBudget extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;

  labels = {
    actions: ACTIONS,
    get title() {
      return helpText('Events', 'Events_Budget_Title');
    },
    get intro() {
      return helpText('Events', 'Events_Budget_Intro');
    },
    get addExpense() {
      return helpText('Events', 'Events_Budget_AddExpense');
    },
    get addFunding() {
      return helpText('Events', 'Events_Budget_AddFunding');
    },
    get expensesEmpty() {
      return helpText('Events', 'Events_Budget_ExpensesEmpty');
    },
    get fundingEmpty() {
      return helpText('Events', 'Events_Budget_FundingEmpty');
    }
  };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.data = await getBudget({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Budget_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get hasData() {
    return Boolean(this.data);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get fieldLabels() {
    return (this.data && this.data.fieldLabels) || {};
  }

  get canAddExpense() {
    return Boolean(this.data && this.data.canAddExpense);
  }

  get canAddFunding() {
    return Boolean(this.data && this.data.canAddFunding);
  }

  get canEdit() {
    return Boolean(this.data && this.data.canEdit);
  }

  rows(kind) {
    const lines = (this.data && this.data[kind]) || [];
    return lines.map((line) => ({
      ...line,
      kind,
      budgetedText: money(line.budgeted),
      actualText: money(line.actual),
      expectedText: money(line.expected),
      receivedText: money(line.received),
      source: [line.organizationName, line.sponsorName].filter(Boolean).join(', '),
      menuLabel: format(ACTIONS_FOR, line.name)
    }));
  }

  get expenseRows() {
    return this.rows('expenses');
  }

  get fundingRows() {
    return this.rows('funding');
  }

  get hasExpenses() {
    return this.expenseRows.length > 0;
  }

  get hasFunding() {
    return this.fundingRows.length > 0;
  }

  get categoryLines() {
    return expenseTotals(this.data && this.data.expenses).categories.map((row) => ({
      key: row.category,
      text: helpText(
        'Events',
        'Events_Budget_CategoryLine',
        row.category,
        money(row.budgeted),
        money(row.actual)
      )
    }));
  }

  get expenseTotalsText() {
    const totals = expenseTotals(this.data && this.data.expenses);
    return helpText('Events', 'Events_Budget_Totals', money(totals.budgeted), money(totals.actual));
  }

  get fundingTotalsText() {
    const totals = fundingTotals(this.data && this.data.funding);
    return helpText(
      'Events',
      'Events_Budget_FundingTotals',
      money(totals.expected),
      money(totals.received)
    );
  }

  get registrationsText() {
    return helpText(
      'Events',
      'Events_Budget_RegistrationsPaid',
      money(this.data && this.data.registrationsPaid)
    );
  }

  get netCostText() {
    return helpText('Events', 'Events_Budget_NetCost', money(netCosts(this.data).netCost));
  }

  get budgetedNetCostText() {
    return helpText(
      'Events',
      'Events_Budget_BudgetedNetCost',
      money(netCosts(this.data).budgetedNetCost)
    );
  }

  get menuItems() {
    return [
      { value: 'edit', label: EDIT },
      { value: 'remove', label: REMOVE }
    ];
  }

  handleAddExpense() {
    this.openForm('Event_Expense__c', EXPENSE_FIELDS, null, this.labels.addExpense);
  }

  handleAddFunding() {
    this.openForm('Event_Funding__c', FUNDING_FIELDS, null, this.labels.addFunding);
  }

  handleMenu(event) {
    const kind = event.target.dataset.kind;
    const line = this.rows(kind).find((row) => row.id === event.target.dataset.id);
    if (!line) {
      return;
    }
    if (event.detail.value === 'remove') {
      this.confirmRemove(line);
      return;
    }
    const isExpense = kind === 'expenses';
    this.openForm(
      isExpense ? 'Event_Expense__c' : 'Event_Funding__c',
      isExpense ? EXPENSE_FIELDS : FUNDING_FIELDS,
      line.id,
      `${EDIT}: ${line.name}`
    );
  }

  async openForm(objectApiName, fields, recordId, label) {
    const saved = await EventRecordModal.open({
      label,
      size: 'small',
      objectApiName,
      recordId,
      fields,
      defaults: recordId ? undefined : { Event__c: this.recordId }
    });
    if (saved) {
      await this.load();
    }
  }

  async confirmRemove(line) {
    const confirmed = await BarnConfirmModal.open({
      label: `${REMOVE}: ${line.name}`,
      message: helpText('Events', 'Events_Budget_RemoveConfirm', line.name),
      confirmLabel: REMOVE,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      size: 'small'
    });
    if (!confirmed) {
      return;
    }
    this.busy = true;
    try {
      await deleteRecord(line.id);
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')),
          variant: 'error'
        })
      );
    } finally {
      this.busy = false;
    }
    await this.load();
  }
}
