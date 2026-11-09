import { LightningElement, api } from 'lwc';
import getForm from '@salesforce/apex/FormPublicController.getForm';
import submit from '@salesforce/apex/FormPublicController.submit';
import saveDraft from '@salesforce/apex/FormPublicController.saveDraft';
import { parseDefinition } from 'c/formDefinition';
import {
  FILE_ACCEPT,
  checkFileSizes,
  checkStep,
  countedAnswers,
  nextStep,
  previousStep,
  questionViews,
  readFiles,
  visibleSteps
} from 'c/formRules';
import { HELP, LABELS, SAVE_TEXT, answerText, publicResultText, trapLabel } from 'c/formText';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { nameTab } from 'c/formPublicPageModel';

/**
 * A public form on a Salesforce Site (C-42b, C-42c; ADR-0184 public forms on a Salesforce Site,
 * decisions 1, 4, 5, 10 and 11), loaded by the `FormsPublic` page through Lightning Out. The same
 * questions, conditions and checks as the staff runner (`c/formRules`, `c/formDefinition`); the
 * answers and files go to `FormPublicController`, which stores them for processing and says only
 * whether they were received. A hidden question a person never sees catches scripts. When the
 * form allows it, a person can save their answers and finish from an emailed link.
 */
export default class FormPublic extends LightningElement {
  /** The form to fill in (the page's `form` parameter). */
  @api formId;
  /** The record the form is filled in for, such as an event (the page's `record` parameter). */
  @api recordId;
  /** The emailed token of saved answers (the page's `resume` parameter). */
  @api resumeToken;
  /** True inside a module's public page (`c/formPublicPage`), which has the page's own heading. */
  @api embedded = false;

  helpReady = isHelpLoaded(HELP);
  labels = LABELS;
  saveText = SAVE_TEXT;
  fileAccept = FILE_ACCEPT;
  form;
  model;
  answers = {};
  files = {};
  problems = {};
  current = -1;
  trap = '';
  busy = false;
  loading = true;
  closedMessage;
  resultMessage;
  noticeMessage;
  done = false;
  saving = false;
  saveEmail = '';
  saveProblem;
  token;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    this.token = this.resumeToken || null;
    this.open();
  }

  async open() {
    this.loading = true;
    try {
      let form = await getForm({ formId: this.formId, resumeToken: this.token });
      if (this.token && !(form && form.definition)) {
        this.noticeMessage = SAVE_TEXT.linkGone;
        this.token = null;
        form = await getForm({ formId: this.formId, resumeToken: null });
      }
      if (form && form.definition) {
        this.form = form;
        this.model = parseDefinition(form.definition).definition;
        this.answers = form.answers ? JSON.parse(form.answers) : {};
        const shown = visibleSteps(this.model, this.answers);
        this.current = shown.includes(form.step) ? form.step : (shown[0] ?? -1);
        if (form.answers) {
          this.noticeMessage = SAVE_TEXT.resumed;
        }
        // Inside a module's page, that page names the tab after its record.
        if (!this.embedded) {
          nameTab(form.name);
        }
      } else {
        this.closedMessage = publicResultText('Closed');
      }
    } catch {
      this.closedMessage = publicResultText('Closed');
    }
    this.loading = false;
  }

  get title() {
    return this.form ? this.form.name : '';
  }

  /** On its own the form is the page, centered with room around it; inside a page it is a section. */
  get containerClass() {
    return this.embedded
      ? 'slds-is-relative'
      : 'slds-is-relative slds-container_large slds-container_center slds-var-p-around_medium';
  }

  get description() {
    return this.form ? this.form.description : '';
  }

  get trapText() {
    return trapLabel();
  }

  get ready() {
    return Boolean(this.model) && this.current >= 0 && !this.done;
  }

  /** Saving for later is offered when the form allows it and was not opened from a record. */
  get canSave() {
    return Boolean(this.form && this.form.canSave) && !this.recordId;
  }

  get pathSteps() {
    return visibleSteps(this.model, this.answers).map((index) => ({
      value: String(index),
      label: this.model.steps[index].title || this.model.steps[index].key
    }));
  }

  get currentValue() {
    return String(this.current);
  }

  get canGoBack() {
    return previousStep(this.model, this.current, this.answers) >= 0;
  }

  get isLast() {
    return nextStep(this.model, this.current, this.answers) < 0;
  }

  get questions() {
    return questionViews(this.model, this.current, this.answers, this.problems).map((question) => ({
      ...question,
      fileName: question.isFile && this.files[question.key] ? this.files[question.key].name : '',
      error: question.problem ? answerText(question.problem) : ''
    }));
  }

  handleAnswer(event) {
    const key = event.target.dataset.key;
    const value =
      event.target.dataset.type === 'checkbox' ? event.detail.checked : event.detail.value;
    this.setAnswer(key, value);
  }

  handleFile(event) {
    const key = event.target.dataset.key;
    const file = (event.detail.files || [])[0];
    const files = { ...this.files };
    if (file) {
      files[key] = file;
    } else {
      delete files[key];
    }
    this.files = files;
    this.setAnswer(key, file ? file.name : '');
  }

  setAnswer(key, value) {
    this.answers = { ...this.answers, [key]: value };
    if (this.problems[key]) {
      const problems = { ...this.problems };
      delete problems[key];
      this.problems = problems;
    }
  }

  handleTrap(event) {
    this.trap = event.target.value;
  }

  stepIsFine() {
    this.problems = checkStep(this.model, this.current, this.answers);
    return Object.keys(this.problems).length === 0;
  }

  handleNext() {
    if (this.stepIsFine()) {
      this.current = nextStep(this.model, this.current, this.answers);
    }
  }

  handleBack() {
    this.problems = {};
    this.current = previousStep(this.model, this.current, this.answers);
  }

  /** The chosen files for the questions that count, read to send, or null when too large. */
  filesToSend(counted) {
    const chosen = {};
    Object.keys(this.files).forEach((key) => {
      if (counted[key] !== undefined) {
        chosen[key] = this.files[key];
      }
    });
    const tooLarge = checkFileSizes(chosen);
    if (Object.keys(tooLarge).length) {
      this.showServerProblems(tooLarge);
      return Promise.resolve(null);
    }
    return readFiles(chosen);
  }

  async handleSubmit() {
    if (!this.stepIsFine()) {
      return;
    }
    this.busy = true;
    this.resultMessage = '';
    try {
      const counted = countedAnswers(this.model, this.answers);
      const files = await this.filesToSend(counted);
      if (files) {
        const receipt = await submit({
          ticket: this.form.ticket,
          answersJson: JSON.stringify(counted),
          trap: this.trap,
          contextRecordId: this.recordId || null,
          filesJson: JSON.stringify(files),
          resumeToken: this.token
        });
        this.showReceipt(receipt, 'Received');
      }
    } catch {
      this.resultMessage = publicResultText('Failed');
    }
    this.busy = false;
  }

  handleSaveOpen() {
    this.saving = !this.saving;
    this.saveProblem = '';
  }

  handleSaveEmail(event) {
    this.saveEmail = event.detail.value;
  }

  async handleSaveSend() {
    this.busy = true;
    this.resultMessage = '';
    this.saveProblem = '';
    try {
      const receipt = await saveDraft({
        ticket: this.form.ticket,
        answersJson: JSON.stringify(countedAnswers(this.model, this.answers)),
        trap: this.trap,
        email: this.saveEmail,
        step: this.current
      });
      if (receipt.status === 'Invalid') {
        const code = (receipt.problems || {}).saveForLater;
        this.saveProblem = answerText({ code, args: [] });
      } else {
        this.showReceipt(receipt, 'Saved');
      }
    } catch {
      this.resultMessage = publicResultText('Failed');
    }
    this.busy = false;
  }

  showReceipt(receipt, finished) {
    if (receipt.status === 'Invalid') {
      this.showServerProblems(receipt.problems || {});
      return;
    }
    this.done = receipt.status === finished;
    this.saving = false;
    this.resultMessage = publicResultText(receipt.status, receipt.message);
  }

  /** Shows problems by field key, given as codes from the server or as `{ code, args }`. */
  showServerProblems(found) {
    const problems = {};
    Object.keys(found).forEach((key) => {
      problems[key] = typeof found[key] === 'string' ? { code: found[key], args: [] } : found[key];
    });
    const first = visibleSteps(this.model, this.answers).find((index) =>
      this.model.steps[index].fields.some((field) => problems[field.key])
    );
    this.current = first === undefined ? this.current : first;
    this.problems = problems;
  }

  get resultVariant() {
    return this.done ? 'success' : 'warning';
  }
}
