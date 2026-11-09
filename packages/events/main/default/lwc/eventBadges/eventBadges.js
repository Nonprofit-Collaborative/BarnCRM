import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import QR_CODE from '@salesforce/resourceUrl/BarnQrCode';
import getBadges from '@salesforce/apex/EventBadgesController.getBadges';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  BLANK_ROWS,
  DEFAULT_LAYOUT,
  LAYOUTS,
  badgePageHtml,
  selectAttendees,
  signInPageHtml,
  ticketNames
} from 'c/eventBadgesModel';

import BADGES from '@salesforce/label/c.Events_EventTab_Badges';

const HELP_PACKAGES = ['Events'];
const QR_CELL_SIZE = 4;
const WHOLE_EVENT = '';
const ALL_TICKETS = '';

/**
 * The Badges tab of the event page (EV-17): printable name badges in a choice of sizes (name,
 * organization, ticket type and an optional QR code, the code the Check-In tab reads) and
 * printable sign-in sheets for the event or one session. Pages are built in the browser
 * (`eventBadgesModel`), opened in a new window and printed there; nothing goes to an outside
 * service. QR codes are drawn by the bundled library.
 */
export default class EventBadges extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  term = '';
  ticket = ALL_TICKETS;
  layout = DEFAULT_LAYOUT;
  showOrganization = true;
  showTicket = true;
  showQr = false;
  sheetScope = WHOLE_EVENT;

  labels = {
    badges: BADGES,
    get intro() {
      return helpText('Events', 'Events_Badges_Intro');
    },
    get empty() {
      return helpText('Events', 'Events_Badges_Empty');
    },
    get emptyHeading() {
      return helpText('Events', 'Events_Badges_EmptyHeading');
    },
    get truncated() {
      return helpText('Events', 'Events_Badges_Truncated');
    },
    get search() {
      return helpText('Events', 'Events_Badges_Search');
    },
    get ticketFilter() {
      return helpText('Events', 'Events_Badges_TicketFilter');
    },
    get allTickets() {
      return helpText('Events', 'Events_Badges_AllTickets');
    },
    get layout() {
      return helpText('Events', 'Events_Badges_Layout');
    },
    get showOrganization() {
      return helpText('Events', 'Events_Badges_ShowOrganization');
    },
    get showTicket() {
      return helpText('Events', 'Events_Badges_ShowTicket');
    },
    get showQr() {
      return helpText('Events', 'Events_Badges_ShowQr');
    },
    get printBadges() {
      return helpText('Events', 'Events_Badges_PrintBadges');
    },
    get sheetHeading() {
      return helpText('Events', 'Events_Badges_SheetHeading');
    },
    get sheetScope() {
      return helpText('Events', 'Events_Badges_SheetScope');
    },
    get wholeEvent() {
      return helpText('Events', 'Events_Badges_WholeEvent');
    },
    get printSheet() {
      return helpText('Events', 'Events_Badges_PrintSheet');
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
      this.data = await getBadges({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Badges_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get attendees() {
    return (this.data && this.data.attendees) || [];
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get truncated() {
    return Boolean(this.data && this.data.truncated);
  }

  get hasAttendees() {
    return this.attendees.length > 0;
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && Boolean(this.data) && !this.hasAttendees;
  }

  get chosen() {
    return selectAttendees(this.attendees, this.term, this.ticket);
  }

  get layoutOptions() {
    const names = {
      large: helpText('Events', 'Events_Badges_LayoutLarge'),
      standard: helpText('Events', 'Events_Badges_LayoutStandard'),
      compact: helpText('Events', 'Events_Badges_LayoutCompact')
    };
    return LAYOUTS.map((item) => ({ value: item.value, label: names[item.value] }));
  }

  get ticketOptions() {
    return [
      { value: ALL_TICKETS, label: this.labels.allTickets },
      ...ticketNames(this.attendees).map((name) => ({ value: name, label: name }))
    ];
  }

  get scopeOptions() {
    return [
      { value: WHOLE_EVENT, label: this.labels.wholeEvent },
      ...((this.data && this.data.sessions) || []).map((session) => ({
        value: session.id,
        label: session.name
      }))
    ];
  }

  get countText() {
    return helpText('Events', 'Events_Badges_Count', this.chosen.length, this.attendees.length);
  }

  get cannotPrintBadges() {
    return this.busy || this.chosen.length === 0;
  }

  get cannotPrintSheet() {
    return this.busy || this.attendees.length === 0;
  }

  handleTerm(event) {
    this.term = event.detail.value || '';
  }

  handleTicket(event) {
    this.ticket = event.detail.value || ALL_TICKETS;
  }

  handleLayout(event) {
    this.layout = event.detail.value;
  }

  handleOrganization(event) {
    this.showOrganization = event.detail.checked;
  }

  handleTicketShown(event) {
    this.showTicket = event.detail.checked;
  }

  handleQr(event) {
    this.showQr = event.detail.checked;
  }

  handleScope(event) {
    this.sheetScope = event.detail.value || WHOLE_EVENT;
  }

  /** Draws each person's QR code in the browser: the code is the attendee's record identifier. */
  async qrFor(people) {
    await loadScript(this, QR_CODE);
    return people.map((person) => {
      const generator = window.qrcode(0, 'M');
      generator.addData(person.id);
      generator.make();
      return generator.createDataURL(QR_CELL_SIZE, 0);
    });
  }

  async handlePrintBadges() {
    this.busy = true;
    try {
      const people = this.chosen;
      const codes = this.showQr ? await this.qrFor(people) : [];
      const badges = people.map((person, index) => ({ ...person, qr: codes[index] }));
      this.openPrint(
        badgePageHtml(this.data.eventName, this.layout, badges, {
          organization: this.showOrganization,
          ticket: this.showTicket,
          qr: this.showQr
        })
      );
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Badges_PrintFailed')), 'error');
    } finally {
      this.busy = false;
    }
  }

  handlePrintSheet() {
    const session = ((this.data && this.data.sessions) || []).find(
      (item) => item.id === this.sheetScope
    );
    const heading = session
      ? helpText('Events', 'Events_Badges_SessionHeading', this.data.eventName, session.name)
      : helpText('Events', 'Events_Badges_EventHeading', this.data.eventName);
    const when = session ? session.startsAt : this.data.eventStart;
    const subheading = [
      when ? new Date(when).toLocaleString() : '',
      session ? session.room : this.data.venue
    ]
      .filter(Boolean)
      .join(', ');
    try {
      this.openPrint(
        signInPageHtml(
          heading,
          subheading,
          this.attendees,
          {
            name: helpText('Events', 'Events_Badges_Name'),
            organization: helpText('Events', 'Events_Badges_Organization'),
            ticket: helpText('Events', 'Events_Badges_Ticket'),
            signature: helpText('Events', 'Events_Badges_Signature')
          },
          BLANK_ROWS
        )
      );
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Badges_PrintFailed')), 'error');
    }
  }

  /** Opens the page in a new window and starts the browser's print dialog there. */
  openPrint(html) {
    const url = URL.createObjectURL(new Blob([html], { type: 'text/html' }));
    const printWindow = window.open(url, '_blank');
    if (!printWindow) {
      URL.revokeObjectURL(url);
      this.toast(helpText('Events', 'Events_Badges_PopupBlocked'), 'warning');
      return;
    }
    printWindow.addEventListener('load', () => {
      printWindow.focus();
      printWindow.print();
    });
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
