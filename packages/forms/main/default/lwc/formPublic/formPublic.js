import { LightningElement, api } from 'lwc';
import getForm from '@salesforce/apex/FormPublicController.getForm';
import submit from '@salesforce/apex/FormPublicController.submit';
import { parseDefinition } from 'c/formDefinition';
import {
  checkStep,
  countedAnswers,
  nextStep,
  previousStep,
  questionViews,
  visibleSteps
} from 'c/formRules';
import { HELP, LABELS, answerText, publicResultText, trapLabel } from 'c/formText';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * A public form on a Salesforce Site (C-42b; ADR-0184 public forms on a Salesforce Site,
 * decisions 1, 4, 5 and 10), loaded by the `FormsPublic` page through Lightning Out. The same
 * questions, conditions and checks as the staff runner (`c/formRules`, `c/formDefinition`); the
 * answers go to `FormPublicController`, which stores them for processing and says only whether
 * they were received. A hidden question a person never sees catches scripts.
 */
export default class FormPublic extends LightningElement {
  /** The form to fill in (the page's `form` parameter). */
  @api formId;
  /** The record the form is filled in for, such as an event (the page's `record` parameter). */
  @api recordId;

  helpReady = isHelpLoaded(HELP);
  labels = LABELS;
  form;
  model;
  answers = {};
  problems = {};
  current = -1;
  trap = '';
  busy = false;
  loading = true;
  closedMessage;
  resultMessage;
  done = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    this.open();
  }

  async open() {
    this.loading = true;
    try {
      const form = await getForm({ formId: this.formId });
      if (form && form.definition) {
        this.form = form;
        this.model = parseDefinition(form.definition).definition;
        this.current = visibleSteps(this.model, {})[0] ?? -1;
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

  get description() {
    return this.form ? this.form.description : '';
  }

  get trapText() {
    return trapLabel();
  }

  get ready() {
    return Boolean(this.model) && this.current >= 0 && !this.done;
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
      error: question.problem ? answerText(question.problem) : ''
    }));
  }

  handleAnswer(event) {
    const key = event.target.dataset.key;
    const value =
      event.target.dataset.type === 'checkbox' ? event.detail.checked : event.detail.value;
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

  async handleSubmit() {
    if (!this.stepIsFine()) {
      return;
    }
    this.busy = true;
    this.resultMessage = '';
    try {
      const receipt = await submit({
        ticket: this.form.ticket,
        answersJson: JSON.stringify(countedAnswers(this.model, this.answers)),
        trap: this.trap,
        contextRecordId: this.recordId || null
      });
      if (receipt.status === 'Invalid') {
        this.showServerProblems(receipt.problems || {});
      } else {
        this.done = receipt.status === 'Received';
        this.resultMessage = publicResultText(receipt.status, receipt.message);
      }
    } catch {
      this.resultMessage = publicResultText('Failed');
    }
    this.busy = false;
  }

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

  get resultVariant() {
    return this.done ? 'success' : 'warning';
  }
}
