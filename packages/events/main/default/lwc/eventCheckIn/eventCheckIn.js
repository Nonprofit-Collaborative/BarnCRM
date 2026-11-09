import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import QR_CODE from '@salesforce/resourceUrl/BarnQrCode';
import getCheckIn from '@salesforce/apex/EventCheckInController.getCheckIn';
import checkIn from '@salesforce/apex/EventCheckInController.checkIn';
import walkIn from '@salesforce/apex/EventCheckInController.walkIn';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  canAddWalkIn,
  counts,
  findByCode,
  visibleAttendees,
  walkInRequest
} from 'c/eventCheckInModel';

import CHECK_IN from '@salesforce/label/c.Events_EventTab_CheckIn';

const HELP_PACKAGES = ['Events', 'Core'];
const SCAN_INTERVAL_MS = 400;
const QR_CELL_SIZE = 6;

/**
 * The Check-In tab of the event page (EV-12): search the people holding a seat and check them
 * in with one click, scan the QR code on a ticket with the device camera where the browser can
 * read codes (or type the code), show an attendee's QR code, and add a walk-in. QR codes are
 * drawn in the browser by a bundled library; nothing goes to an outside service.
 */
export default class EventCheckIn extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  term = '';
  code = '';
  scanning = false;
  walkInOpen = false;
  walkInForm = {};
  qrFor;
  qrImage;
  stream;
  timer;

  labels = {
    checkIn: CHECK_IN,
    get intro() {
      return helpText('Events', 'Events_CheckIn_Intro');
    },
    get empty() {
      return helpText('Events', 'Events_CheckIn_Empty');
    },
    get noMatch() {
      return helpText('Events', 'Events_CheckIn_NoMatch');
    },
    get search() {
      return helpText('Events', 'Events_CheckIn_Search');
    },
    get scan() {
      return helpText('Events', 'Events_CheckIn_Scan');
    },
    get stopScan() {
      return helpText('Events', 'Events_CheckIn_StopScan');
    },
    get codeLabel() {
      return helpText('Events', 'Events_CheckIn_CodeLabel');
    },
    get codeSubmit() {
      return helpText('Events', 'Events_CheckIn_CodeSubmit');
    },
    get name() {
      return helpText('Events', 'Events_CheckIn_Name');
    },
    get email() {
      return helpText('Events', 'Events_CheckIn_Email');
    },
    get ticket() {
      return helpText('Events', 'Events_CheckIn_Ticket');
    },
    get status() {
      return helpText('Events', 'Events_CheckIn_Status');
    },
    get walkIn() {
      return helpText('Events', 'Events_CheckIn_WalkIn');
    },
    get firstName() {
      return helpText('Events', 'Events_CheckIn_FirstName');
    },
    get lastName() {
      return helpText('Events', 'Events_CheckIn_LastName');
    },
    get walkInAdd() {
      return helpText('Events', 'Events_CheckIn_WalkInAdd');
    },
    get close() {
      return helpText('Events', 'Events_CheckIn_Close');
    },
    get truncated() {
      return helpText('Events', 'Events_CheckIn_Truncated');
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

  disconnectedCallback() {
    this.stopScan();
  }

  async load() {
    this.isLoading = true;
    try {
      this.data = await getCheckIn({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_CheckIn_LoadFailed'));
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

  get canCheckIn() {
    return Boolean(this.data && this.data.canCheckIn);
  }

  get canWalkIn() {
    return Boolean(this.data && this.data.canWalkIn);
  }

  get showWalkInButton() {
    return this.canWalkIn && !this.walkInOpen;
  }

  get ticketOptions() {
    return (this.data && this.data.tickets) || [];
  }

  get hasTickets() {
    return this.ticketOptions.length > 0;
  }

  get cannotAddWalkIn() {
    return this.busy || !canAddWalkIn(this.walkInForm);
  }

  get summaryText() {
    const total = counts(this.attendees);
    return helpText(
      'Events',
      'Events_CheckIn_Summary',
      total.checkedIn,
      total.total,
      total.remaining
    );
  }

  /** Whether this browser can read QR codes from the camera. */
  get canScan() {
    return typeof window !== 'undefined' && 'BarcodeDetector' in window;
  }

  get cameraHelp() {
    return this.canScan ? '' : helpText('Events', 'Events_CheckIn_ScanUnavailable');
  }

  get showCameraHelp() {
    return !this.canScan;
  }

  get showScanButton() {
    return this.canScan && this.canCheckIn && !this.scanning;
  }

  get rows() {
    return visibleAttendees(this.attendees, this.term).map((attendee) => ({
      ...attendee,
      buttonLabel: attendee.checkedIn
        ? helpText('Events', 'Events_CheckIn_Undo')
        : helpText('Events', 'Events_CheckIn_CheckIn'),
      buttonVariant: attendee.checkedIn ? 'neutral' : 'brand',
      qrLabel: helpText('Events', 'Events_CheckIn_ShowQr', attendee.name),
      href: `/lightning/r/${attendee.id}/view`
    }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showNoMatch() {
    return this.hasAttendees && !this.hasRows;
  }

  get showQr() {
    return Boolean(this.qrFor && this.qrImage);
  }

  get qrTitle() {
    return this.qrFor ? helpText('Events', 'Events_CheckIn_QrFor', this.qrFor.name) : '';
  }

  handleTerm(event) {
    this.term = event.detail.value || '';
  }

  handleCode(event) {
    this.code = event.detail.value || '';
  }

  /** Enter checks the code in, so a handheld scanner that types the code and Enter just works. */
  handleCodeKey(event) {
    if (event.key === 'Enter' && this.code && !this.busy) {
      event.preventDefault();
      this.handleSubmitCode();
    }
  }

  async handleSubmitCode() {
    const text = this.code;
    this.code = '';
    await this.checkInCode(text);
  }

  /** Checks in whoever the code (scanned or typed) belongs to. */
  async checkInCode(text) {
    const attendee = findByCode(this.attendees, text);
    if (!attendee) {
      this.toast(helpText('Events', 'Events_CheckIn_NotFound'), 'warning');
      return;
    }
    if (attendee.status === 'Attended') {
      this.toast(helpText('Events', 'Events_CheckIn_AlreadyIn', attendee.name), 'info');
      return;
    }
    await this.change(attendee, false);
  }

  async handleToggle(event) {
    const attendee = this.attendees.find((item) => item.id === event.currentTarget.dataset.id);
    if (attendee) {
      await this.change(attendee, attendee.status === 'Attended');
    }
  }

  async change(attendee, undo) {
    await this.run(async () => {
      await checkIn({ attendeeId: attendee.id, undo });
      this.toast(
        undo
          ? helpText('Events', 'Events_CheckIn_Undone', attendee.name)
          : helpText('Events', 'Events_CheckIn_Done', attendee.name),
        'success'
      );
    });
  }

  async handleShowQr(event) {
    const attendee = this.attendees.find((item) => item.id === event.currentTarget.dataset.id);
    if (!attendee) {
      return;
    }
    try {
      await loadScript(this, QR_CODE);
      const generator = window.qrcode(0, 'M');
      generator.addData(attendee.id);
      generator.make();
      this.qrImage = generator.createDataURL(QR_CELL_SIZE, 2 * QR_CELL_SIZE);
      this.qrFor = attendee;
    } catch {
      this.qrFor = undefined;
      this.qrImage = undefined;
      this.toast(helpText('Events', 'Events_CheckIn_QrFailed'), 'error');
    }
  }

  handleHideQr() {
    this.qrFor = undefined;
    this.qrImage = undefined;
  }

  async handleScan() {
    try {
      const detector = new window.BarcodeDetector({ formats: ['qr_code'] });
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment' }
      });
      this.scanning = true;
      await Promise.resolve();
      const video = this.template.querySelector('[data-id="scan-video"]');
      video.srcObject = this.stream;
      await video.play();
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.timer = setInterval(() => this.readFrame(detector, video), SCAN_INTERVAL_MS);
    } catch {
      this.stopScan();
      this.toast(helpText('Events', 'Events_CheckIn_ScanFailed'), 'error');
    }
  }

  async readFrame(detector, video) {
    if (this.busy || !this.scanning) {
      return;
    }
    try {
      const found = await detector.detect(video);
      if (found.length) {
        this.stopScan();
        await this.checkInCode(found[0].rawValue);
      }
    } catch {
      // A frame that cannot be read is skipped; the next one is tried.
    }
  }

  handleStopScan() {
    this.stopScan();
  }

  stopScan() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop());
      this.stream = undefined;
    }
    this.scanning = false;
  }

  handleOpenWalkIn() {
    this.walkInForm = { ticketTypeId: this.hasTickets ? this.ticketOptions[0].value : null };
    this.walkInOpen = true;
  }

  handleCloseWalkIn() {
    this.walkInOpen = false;
  }

  handleWalkInField(event) {
    this.walkInForm = { ...this.walkInForm, [event.target.dataset.field]: event.detail.value };
  }

  async handleAddWalkIn() {
    const request = walkInRequest(this.recordId, this.walkInForm);
    await this.run(async () => {
      await walkIn({ requestJson: JSON.stringify(request) });
      this.walkInOpen = false;
      this.toast(
        helpText(
          'Events',
          'Events_CheckIn_WalkInDone',
          [request.registrant.firstName, request.registrant.lastName].filter(Boolean).join(' ')
        ),
        'success'
      );
    });
  }

  /** Runs a change, then reloads; a refusal shows in a toast in plain words. */
  async run(change) {
    this.busy = true;
    try {
      await change();
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')), 'error');
    } finally {
      this.busy = false;
    }
    await this.load();
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
