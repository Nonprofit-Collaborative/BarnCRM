import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPublishedForms from '@salesforce/apex/FormRunnerController.getPublishedForms';
import getForm from '@salesforce/apex/FormRunnerController.getForm';
import submit from '@salesforce/apex/FormRunnerController.submit';
import { parseDefinition } from 'c/formDefinition';
import {
  checkStep,
  countedAnswers,
  nextStep,
  previousStep,
  visibility,
  visibleSteps
} from 'c/formRules';
import { HELP, LABELS, answerText, messageFrom, resultText } from 'c/formText';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

const INPUT_TYPES = { text: 'text', email: 'email', phone: 'tel', number: 'number', date: 'date' };

/**
 * The Form Runner (C-42a; ADR-NEXT `NEXT-forms-module.md`, decision 12): a published form filled
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
    const shown = visibility(this.model, this.answers);
    const step = this.model.steps[this.current];
    return step.fields
      .filter((field) => shown[field.key])
      .map((field) => {
        const problem = this.problems[field.key];
        return {
          key: field.key,
          label: field.label,
          help: field.help,
          required: field.required,
          value: this.answers[field.key] === undefined ? '' : this.answers[field.key],
          checked: this.answers[field.key] === true,
          isCheckbox: field.type === 'checkbox',
          isLong: field.type === 'textarea',
          isPicklist: field.type === 'picklist',
          isInput: Boolean(INPUT_TYPES[field.type]),
          inputType: INPUT_TYPES[field.type],
          options: (field.options || []).map((option) => ({
            value: String(option.value),
            label: option.label || String(option.value)
          })),
          error: problem ? answerText(problem) : '',
          className: problem ? 'slds-form-element slds-has-error' : 'slds-form-element'
        };
      });
  }

  handleAnswer(event) {
    const key = event.target.dataset.key;
    const value =
      event.target.type === 'checkbox' || event.target.dataset.type === 'checkbox'
        ? event.detail.checked
        : event.detail.value;
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
      const result = await submit({
        formId: this.form.formId,
        answersJson: JSON.stringify(countedAnswers(this.model, this.answers)),
        contextRecordId: this.contextId
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
  showServerProblems(codes) {
    const problems = {};
    Object.keys(codes).forEach((key) => {
      problems[key] = { code: codes[key], args: [] };
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
