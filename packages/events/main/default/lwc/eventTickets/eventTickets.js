import { LightningElement, api } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getTickets from '@salesforce/apex/EventTicketsController.getTickets';
import { whenText } from 'c/eventsModel';
import { codeState, quantitySummary } from 'c/eventTicketsModel';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import EventRecordModal from 'c/eventRecordModal';
import BarnConfirmModal from 'c/barnConfirmModal';

import TICKETS from '@salesforce/label/c.Events_EventTab_Tickets';
import NEW_TICKET from '@salesforce/label/c.Events_Tickets_NewTicketType';
import NEW_CODE from '@salesforce/label/c.Events_Tickets_NewPromoCode';
import EXPIRED from '@salesforce/label/c.Events_Tickets_Expired';
import SCHEDULED from '@salesforce/label/c.Events_Tickets_Scheduled';
import NO_LIMIT from '@salesforce/label/c.Events_Tickets_NoLimit';
import ACTIVE from '@salesforce/label/c.Core_MatchLogic_Active';
import INACTIVE from '@salesforce/label/c.Core_MatchLogic_Inactive';
import ALL from '@salesforce/label/c.Core_DataJobs_ShowAll';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import DELETE from '@salesforce/label/c.Core_Find_Delete';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import WHEN from '@salesforce/label/c.Core_FieldAccess_ColWhen';
import DATE_RANGE from '@salesforce/label/c.Core_Address_DateRange';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';

const HELP_PACKAGES = ['Events'];
const TICKET = 'Ticket_Type__c';
const CODE = 'Promo_Code__c';
const TICKET_FIELDS = [
  'Name',
  'Price__c',
  'Quantity__c',
  'Sales_Start__c',
  'Sales_End__c',
  'Active__c',
  'Sort_Order__c',
  'Description__c'
];
const CODE_FIELDS = [
  'Name',
  'Discount_Type__c',
  'Discount_Value__c',
  'Ticket_Type__c',
  'Max_Uses__c',
  'Valid_From__c',
  'Valid_Until__c',
  'Active__c'
];
const STATE_BADGES = {
  active: { status: 'active', label: ACTIVE },
  inactive: { status: 'inactive', label: INACTIVE },
  scheduled: { status: 'neutral', label: SCHEDULED },
  expired: { status: 'closed', label: EXPIRED }
};

/**
 * The Tickets tab of the event page (EV-03): the event's ticket types with price, quantity and
 * sales window, the total of their quantities beside the event's capacity (R-TT4), and its promo
 * codes with their discount and state. Records are added and edited in `eventRecordModal` and
 * deleted after a confirm, all through the platform, so access and validation rules apply.
 */
export default class EventTickets extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  ticketRows = [];
  codeRows = [];
  isLoading = true;
  errorMessage;

  labels = {
    tickets: TICKETS,
    newTicket: NEW_TICKET,
    newCode: NEW_CODE,
    when: WHEN,
    actions: ACTIONS,
    get intro() {
      return helpText('Events', 'Events_Tickets_Intro');
    },
    get noTickets() {
      return helpText('Events', 'Events_Tickets_NoTickets');
    },
    get noCodes() {
      return helpText('Events', 'Events_Tickets_NoCodes');
    },
    get noTicketsHeading() {
      return helpText('Events', 'Events_Tickets_NoTicketsHeading');
    },
    get noCodesHeading() {
      return helpText('Events', 'Events_Tickets_NoCodesHeading');
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
      this.data = await getTickets({ eventId: this.recordId });
      this.errorMessage = undefined;
      this.decorate();
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Tickets_LoadFailed'));
      this.ticketRows = [];
      this.codeRows = [];
    } finally {
      this.isLoading = false;
    }
  }

  decorate() {
    const money = new Intl.NumberFormat(LOCALE, {
      style: 'currency',
      currency: this.data.currencyCode || 'USD'
    });
    const percent = new Intl.NumberFormat(LOCALE, { style: 'percent', maximumFractionDigits: 2 });
    const names = new Map();
    this.ticketRows = (this.data.tickets || []).map((ticket) => {
      names.set(ticket.id, ticket.name);
      return {
        ...ticket,
        priceText: money.format(ticket.price || 0),
        quantityText: this.isEmpty(ticket.quantity) ? NO_LIMIT : String(ticket.quantity),
        windowText: this.windowText(ticket.salesStart, ticket.salesEnd),
        badge: STATE_BADGES[ticket.active ? 'active' : 'inactive'],
        menuLabel: format(ACTIONS_FOR, ticket.name)
      };
    });
    this.codeRows = (this.data.codes || []).map((code) => ({
      ...code,
      discountText:
        code.discountType === 'Amount'
          ? money.format(code.discountValue || 0)
          : percent.format((code.discountValue || 0) / 100),
      ticketText: code.ticketTypeId ? names.get(code.ticketTypeId) || '' : ALL,
      usesText: this.isEmpty(code.maxUses) ? NO_LIMIT : String(code.maxUses),
      windowText: this.windowText(code.validFrom, code.validUntil),
      badge: STATE_BADGES[codeState(code)],
      menuLabel: format(ACTIONS_FOR, code.code)
    }));
  }

  isEmpty(value) {
    return value === null || value === undefined;
  }

  windowText(start, end) {
    if (start) {
      return whenText(start, end, { locale: LOCALE, timeZone: TIME_ZONE, range: DATE_RANGE });
    }
    return end
      ? helpText(
          'Events',
          'Events_Tickets_Until',
          whenText(end, null, { locale: LOCALE, timeZone: TIME_ZONE })
        )
      : '';
  }

  get menuItems() {
    return [
      { label: EDIT, value: 'edit' },
      { label: DELETE, value: 'delete' }
    ];
  }

  get ticketLabels() {
    return this.objectLabels(TICKET);
  }

  get codeLabels() {
    return this.objectLabels(CODE);
  }

  objectLabels(objectName) {
    const all = (this.data && this.data.fieldLabels) || {};
    const result = {};
    Object.keys(all)
      .filter((key) => key.startsWith(`${objectName}.`))
      .forEach((key) => {
        result[key.slice(objectName.length + 1)] = all[key];
      });
    return result;
  }

  get codesTitle() {
    return (this.data && this.data.codesTitle) || '';
  }

  get canAddTicket() {
    return Boolean(this.data && this.data.canAddTicket);
  }

  get canAddCode() {
    return Boolean(this.data && this.data.canAddCode);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get hasTickets() {
    return this.ticketRows.length > 0;
  }

  get hasCodes() {
    return this.codeRows.length > 0;
  }

  get showContent() {
    return !this.isLoading && !this.hasError;
  }

  /** The R-TT4 warning, or null while the quantities fit the capacity. */
  get capacityWarning() {
    if (!this.data) {
      return null;
    }
    const summary = quantitySummary(this.data.tickets, this.data.capacity);
    return summary.overCapacity
      ? helpText('Events', 'Events_Tickets_OverCapacity', summary.total, this.data.capacity)
      : null;
  }

  handleNewTicket() {
    this.openForm(TICKET, null, NEW_TICKET);
  }

  handleNewCode() {
    this.openForm(CODE, null, NEW_CODE);
  }

  handleTicketMenu(event) {
    this.handleMenu(event, TICKET, this.ticketRows);
  }

  handleCodeMenu(event) {
    this.handleMenu(event, CODE, this.codeRows);
  }

  handleMenu(event, objectName, rows) {
    const row = rows.find((candidate) => candidate.id === event.target.dataset.id);
    if (!row) {
      return;
    }
    const name = row.name || row.code;
    if (event.detail.value === 'delete') {
      this.confirmDelete(row.id, name);
    } else {
      this.openForm(objectName, row.id, `${EDIT}: ${name}`);
    }
  }

  async openForm(objectName, recordId, label) {
    const saved = await EventRecordModal.open({
      label,
      size: 'small',
      objectApiName: objectName,
      recordId,
      fields: objectName === TICKET ? TICKET_FIELDS : CODE_FIELDS,
      defaults: { Event__c: this.recordId }
    });
    if (saved) {
      await this.load();
    }
  }

  async confirmDelete(recordId, name) {
    const confirmed = await BarnConfirmModal.open({
      label: `${DELETE}: ${name}`,
      message: helpText('Events', 'Events_Shared_DeleteConfirm', name),
      confirmLabel: DELETE,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      size: 'small'
    });
    if (!confirmed) {
      return;
    }
    try {
      await deleteRecord(recordId);
      await this.load();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')),
          variant: 'error'
        })
      );
    }
  }
}
