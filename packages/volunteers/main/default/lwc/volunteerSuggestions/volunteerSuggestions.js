import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSuggestions from '@salesforce/apex/VolunteerSuggestionController.getSuggestions';
import addSignup from '@salesforce/apex/VolunteerShiftSignupsController.addSignup';
import { rankSuggestions, REASON } from './rankSuggestions';

import TITLE from '@salesforce/label/c.Volunteers_Suggestions_Title';
import SUBTITLE from '@salesforce/label/c.Volunteers_Suggestions_Subtitle';
import EMPTY from '@salesforce/label/c.Volunteers_Suggestions_Empty';
import PERSON from '@salesforce/label/c.Volunteers_Suggestions_Person';
import WHY from '@salesforce/label/c.Volunteers_Suggestions_Why';
import ACTIONS from '@salesforce/label/c.Volunteers_Suggestions_Actions';
import SIGN_UP from '@salesforce/label/c.Volunteers_Suggestions_SignUp';
import SIGN_UP_FOR from '@salesforce/label/c.Volunteers_Suggestions_SignUpFor';
import BOOKED from '@salesforce/label/c.Volunteers_Suggestions_Booked';
import BOOK_FAILED from '@salesforce/label/c.Volunteers_Suggestions_BookFailed';
import LOAD_FAILED from '@salesforce/label/c.Volunteers_Suggestions_LoadFailed';
import MORE_CONSIDERED from '@salesforce/label/c.Volunteers_Suggestions_MoreConsidered';
import R_SKILLS from '@salesforce/label/c.Volunteers_Suggestions_ReasonSkills';
import R_INTERESTS from '@salesforce/label/c.Volunteers_Suggestions_ReasonInterests';
import R_AVAILABLE from '@salesforce/label/c.Volunteers_Suggestions_ReasonAvailable';
import R_UNAVAILABLE from '@salesforce/label/c.Volunteers_Suggestions_ReasonUnavailable';
import R_NO_AVAILABILITY from '@salesforce/label/c.Volunteers_Suggestions_ReasonNoAvailability';
import R_HOURS from '@salesforce/label/c.Volunteers_Suggestions_ReasonHours';
import R_CLEARED from '@salesforce/label/c.Volunteers_Suggestions_ReasonCleared';
import R_OPEN from '@salesforce/label/c.Volunteers_Suggestions_ReasonOpen';
import LOADING from '@salesforce/label/c.Volunteers_Loading';

/** How many suggestions the card shows. */
const MAX_SHOWN = 10;
/** Told to the Sign-ups panel on the same page, so it reloads (see shiftSignups.js). */
const SIGNUPS_CHANGED = 'barnshiftsignupschanged';

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

/**
 * Suggested Volunteers on a shift (V-11): active people not yet signed up, best match first,
 * each with the reasons, and a button that signs them up through the Sign-ups panel's own save.
 * The ranking is the framework-free `rankSuggestions` module; Apex only gathers the facts.
 */
export default class VolunteerSuggestions extends NavigationMixin(LightningElement) {
  @api recordId;

  labels = {
    title: TITLE,
    subtitle: SUBTITLE,
    empty: EMPTY,
    person: PERSON,
    why: WHY,
    actions: ACTIONS,
    loading: LOADING
  };

  data;
  ranked = [];
  loading = true;
  busy = false;
  errorMessage;
  resultMessage;

  connectedCallback() {
    this.load();
  }

  load() {
    this.loading = true;
    return getSuggestions({ shiftId: this.recordId })
      .then((data) => {
        this.data = data;
        this.ranked = data.canBook
          ? rankSuggestions(
              { weekday: data.weekday, requiredSkillIds: data.requiredSkillIds },
              data.candidates
            )
          : [];
      })
      .catch(() => {
        this.errorMessage = LOAD_FAILED;
      })
      .finally(() => {
        this.loading = false;
      });
  }

  /** Nothing at all for a user who cannot book or a shift that is not Open. */
  get visible() {
    return !!(this.errorMessage || (this.data && this.data.canBook));
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get isEmpty() {
    return !!this.data && this.data.canBook && this.ranked.length === 0;
  }

  get hasRows() {
    return this.ranked.length > 0;
  }

  get showSpinner() {
    return this.loading || this.busy;
  }

  get moreNote() {
    return this.data && this.data.moreThanConsidered
      ? format(MORE_CONSIDERED, this.data.candidates.length)
      : undefined;
  }

  get rows() {
    return this.ranked.slice(0, MAX_SHOWN).map((row, index) => ({
      personId: row.personId,
      name: row.name,
      rank: index + 1,
      reasons: row.reasons.map((reason, i) => ({
        key: `${row.personId}-${i}`,
        text: this.reasonText(reason)
      })),
      signUpFor: format(SIGN_UP_FOR, row.name),
      signUp: SIGN_UP
    }));
  }

  reasonText(reason) {
    switch (reason.code) {
      case REASON.SKILLS:
        return format(R_SKILLS, reason.matched, reason.total);
      case REASON.INTERESTS:
        return format(R_INTERESTS, reason.matched, reason.total);
      case REASON.AVAILABLE_DAY:
        return format(R_AVAILABLE, reason.day);
      case REASON.UNAVAILABLE_DAY:
        return format(R_UNAVAILABLE, reason.day);
      case REASON.NO_AVAILABILITY:
        return R_NO_AVAILABILITY;
      case REASON.HOURS_ON_JOB:
        return format(R_HOURS, reason.hours);
      case REASON.ONBOARDING_CLEARED:
        return R_CLEARED;
      case REASON.ONBOARDING_OPEN:
        return R_OPEN;
      default:
        return '';
    }
  }

  handleSignUp(event) {
    const personId = event.currentTarget.dataset.personId;
    const row = this.ranked.find((candidate) => candidate.personId === personId);
    this.busy = true;
    this.errorMessage = undefined;
    this.resultMessage = undefined;
    addSignup({ shiftId: this.recordId, personId, status: null })
      .then(() => {
        this.resultMessage = format(BOOKED, row ? row.name : '');
        window.dispatchEvent(
          new CustomEvent(SIGNUPS_CHANGED, { detail: { shiftId: this.recordId } })
        );
        return this.load();
      })
      .catch((error) => {
        this.errorMessage = this.messageFrom(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  messageFrom(error) {
    const body = error && error.body;
    if (body && typeof body.message === 'string' && body.message) {
      return body.message;
    }
    return BOOK_FAILED;
  }
}
