import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPublishedForms from '@salesforce/apex/FormRunnerController.getPublishedForms';
import getForm from '@salesforce/apex/FormRunnerController.getForm';
import submit from '@salesforce/apex/FormRunnerController.submit';
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
import { HELP, LABELS, answerText, messageFrom, resultText } from 'c/formText';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The Form Runner (C-42a; ADR-0175 `0175-forms-module.md`, decision 12): a published form filled
 * in a step at a time, its conditions and answer checks run with `c/formRules` as the person
 * types, and the answers sent to `FormSubmitService`, which checks them again and writes the
 * records. On a record page it fills in the form a module attached to that record; on an app
 * page or tab it offers the published forms. Given a `definition`, it previews it and sends
 * nothing (the Form Builder's Preview).
 */
export default class FormRunner extends NavigationMixin(LightningElement) {
  /** The record the form is filled in from, on a record page; on a form's own page, the form. */
  @api recordId;
  @api objectApiName;
  /** A form to fill in, set on an app page; otherwise the person picks one. */
  @api formId;
  /** A definition's JSON to preview: the steps show and nothing is sent. */
  @api
  get definition() {
    return this.previewText;
  }
  set definition(value) {
    this.previewText = value;
    if (value !== undefined) {
      this.start(parseDefinition(value).definition, null);
    }
  }

  helpReady = isHelpLoaded(HELP);
  labels = LABELS;
  fileAccept = FILE_ACCEPT;
  files = {};
  previewText;
  formOptions = [];
  chosenFormId;
  form;
  model;
  answers = {};
  problems = {};
  current = -1;
  busy = false;
  loading = false;
  errorMessage;
  result;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    if (this.previewText === undefined && (this.startFormId || this.contextId)) {
      this.open(this.startFormId);
    }
  }

  get onFormPage() {
    return this.objectApiName === 'Form__c';
  }

  /** The form to open at once: the one set, or the form whose page this is. */
  get startFormId() {
    return this.formId || (this.onFormPage ? this.recordId : null) || null;
  }

  /** The record filled in from: never the form itself. */
  get contextId() {
    return this.onFormPage ? null : this.recordId || null;
  }

  @wire(getPublishedForms)
  wiredForms({ data, error }) {
    if (data) {
      this.formOptions = data.map((option) => ({ value: option.id, label: option.name }));
    } else if (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get isPreview() {
    return this.previewText !== undefined;
  }

  get showPicker() {
    // On a record page with no form attached, the person picks one to fill in from it.
    return (
      !this.isPreview && !this.startFormId && !this.loading && !(this.form && this.form.definition)
    );
  }

  get pickerOptions() {
    return this.formOptions;
  }

  handlePick(event) {
    this.chosenFormId = event.detail.value;
    this.open(this.chosenFormId);
  }

  async open(formId) {
    this.loading = true;
    this.errorMessage = '';
    try {
      const form = await getForm({ formId, contextRecordId: this.contextId });
      this.form = form;
      if (form && form.definition) {
        this.start(parseDefinition(form.definition).definition, form);
      } else if (form) {
        this.errorMessage = LABELS.notPublished;
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
    this.loading = false;
  }

  start(definition, form) {
    this.model = definition;
    this.form = form || this.form;
    this.answers = {};
    this.files = {};
    this.problems = {};
    this.result = null;
    this.current = definition ? (visibleSteps(definition, {})[0] ?? -1) : -1;
  }

  get title() {
    return this.form ? this.form.name : LABELS.runnerTitle;
  }

  get ready() {
    return Boolean(this.model) && this.current >= 0 && !this.result;
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

  get submitDisabled() {
    return this.busy || this.isPreview || (this.form && !this.form.canSubmit);
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
      event.target.type === 'checkbox' || event.target.dataset.type === 'checkbox'
        ? event.detail.checked
        : event.detail.value;
    this.setAnswer(key, value);
  }

  /** A file chosen for a file question (C-42c): its name is the answer, the file goes beside. */
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

  /** Checks the step; true when it can go on, else its problems show. */
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

  async handleSubmit() {
    if (!this.stepIsFine() || this.isPreview) {
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    try {
      const counted = countedAnswers(this.model, this.answers);
      const chosen = {};
      Object.keys(this.files).forEach((key) => {
        if (counted[key] !== undefined) {
          chosen[key] = this.files[key];
        }
      });
      const tooLarge = checkFileSizes(chosen);
      if (Object.keys(tooLarge).length) {
        this.showServerProblems(tooLarge);
        this.busy = false;
        return;
      }
      const result = await submit({
        formId: this.form.formId,
        answersJson: JSON.stringify(counted),
        contextRecordId: this.contextId,
        filesJson: JSON.stringify(await readFiles(chosen))
      });
      if (result.status === 'Invalid') {
        this.showServerProblems(result.problems || {});
      } else {
        this.result = result;
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
    this.busy = false;
  }

  /** Answers the server refused: back to the first step with one, problems showing. */
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

  get resultMessage() {
    return this.result ? resultText(this.result) : '';
  }

  get resultVariant() {
    return this.result && this.result.status === 'Processed' ? 'success' : 'warning';
  }

  handleOpenSubmission() {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId: this.result.submissionId, actionName: 'view' }
    });
  }

  handleAnother() {
    this.start(this.model, this.form);
  }
}
