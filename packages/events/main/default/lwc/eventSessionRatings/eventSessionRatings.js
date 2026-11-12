import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import QR_CODE from '@salesforce/resourceUrl/BarnQrCode';
import getSetup from '@salesforce/apex/EventSessionRatings.getSetup';
import saveForm from '@salesforce/apex/EventSessionRatings.saveForm';
import { messageFrom } from 'c/findCsv';
import { helpText } from 'c/barnHelpText';
import { ratingCodesPageHtml } from 'c/eventBadgesModel';
import SAVE from '@salesforce/label/c.Core_Kit_Save';

const QR_CELL_SIZE = 6;

/**
 * The Agenda tab's Session Ratings panel (EV-27): chooses the event's rating form (a published
 * public Forms form) and prints each confirmed session's QR code, drawn in the browser, on a page
 * of its own. Shows nothing without Forms. The agenda passes its session cards in `sessions`
 * (`{ id, name, whenText, room }`); the help catalog is loaded by the agenda.
 */
export default class EventSessionRatings extends LightningElement {
  @api recordId;
  @api eventName;
  @api sessions = [];

  setup;
  open = false;
  busy = false;
  chosenKey = '';

  text = {
    save: SAVE,
    get sessionRatings() {
      return helpText('Events', 'Events_Agenda_SessionRatings');
    },
    get intro() {
      return helpText('Events', 'Events_Agenda_RatingsIntro');
    },
    get form() {
      return helpText('Events', 'Events_Agenda_RatingForm');
    },
    get print() {
      return helpText('Events', 'Events_Agenda_PrintRatingCodes');
    }
  };

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.setup = await getSetup({ eventId: this.recordId });
      this.chosenKey = (this.setup && this.setup.formKey) || '';
    } catch (error) {
      this.setup = undefined;
      this.toast(messageFrom(error, helpText('Events', 'Events_Agenda_LoadFailed')), 'error');
    }
  }

  get cappedText() {
    return helpText(
      'Events',
      'Events_Agenda_RatingCodesCapped',
      this.setup && this.setup.linkLimit
    );
  }

  get available() {
    return Boolean(this.setup && this.setup.available);
  }

  get formOptions() {
    return [
      { label: helpText('Events', 'Events_Agenda_NoRatingForm'), value: '' },
      ...((this.setup && this.setup.forms) || []).map((form) => ({
        label: form.label,
        value: form.key
      }))
    ];
  }

  handleToggle() {
    this.open = !this.open;
  }

  handleForm(event) {
    this.chosenKey = event.detail.value;
  }

  async handleSave() {
    this.busy = true;
    try {
      await saveForm({ eventId: this.recordId, formKey: this.chosenKey });
      this.toast(helpText('Events', 'Events_Agenda_RatingFormSaved'), 'success');
      await this.load();
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')), 'error');
    } finally {
      this.busy = false;
    }
  }

  async handlePrint() {
    const links = (this.setup && this.setup.links) || {};
    const printable = (this.sessions || []).filter((session) => links[session.id]);
    if (!printable.length) {
      this.toast(helpText('Events', 'Events_Agenda_NoRatingCodes'), 'warning');
      return;
    }
    this.busy = true;
    try {
      await loadScript(this, QR_CODE);
      const pages = printable.map((session) => {
        const generator = window.qrcode(0, 'M');
        generator.addData(links[session.id]);
        generator.make();
        return { ...session, qr: generator.createDataURL(QR_CELL_SIZE, 0) };
      });
      this.openPrint(
        ratingCodesPageHtml(
          this.eventName || this.text.sessionRatings,
          helpText('Events', 'Events_Agenda_RateThisSession'),
          pages
        )
      );
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Badges_PrintFailed')), 'error');
    } finally {
      this.busy = false;
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
