import { LightningElement, api } from 'lwc';
import getRuns from '@salesforce/apex/ConnectorRecipesController.getRuns';
import getRun from '@salesforce/apex/ConnectorRecipesController.getRun';
import retryRun from '@salesforce/apex/ConnectorRecipesController.retryRun';
import { stepRows, statusVariant, runAsKey } from 'c/connectorRecipeRules';
import { say as text } from 'c/connectorRecipeText';

/**
 * Run History of Super Connector (CN-02; canonical model R-RUN1 to R-RUN4; design Section 3.7):
 * the latest runs of every recipe, newest first; one opened shows each step's outcome, time,
 * records, the app's status and trimmed answer, and for a Test what each step would have done.
 * A failed run can be retried from its failed step by a Connector admin.
 */
export default class ConnectorRuns extends LightningElement {
  /** Whether Retry is offered (the page's Connector admin flag). */
  @api canManage = false;

  runs;
  opened;
  working = false;
  message;
  error;

  labels = {
    get heading() {
      return text('Connector_Runs_Heading');
    },
    get intro() {
      return text('Connector_Runs_Intro');
    },
    get refresh() {
      return text('Connector_Runs_Refresh');
    },
    get empty() {
      return text('Connector_Runs_Empty');
    },
    get open() {
      return text('Connector_Runs_Open');
    },
    get retry() {
      return text('Connector_Runs_Retry');
    },
    get back() {
      return text('Connector_Runs_Back');
    },
    get steps() {
      return text('Connector_Runs_Steps');
    },
    get response() {
      return text('Connector_Runs_Response');
    },
    get wouldDo() {
      return text('Connector_Runs_WouldDo');
    }
  };

  connectedCallback() {
    this.load();
  }

  async load() {
    this.error = undefined;
    this.working = true;
    try {
      this.runs = (await getRuns({ recipeId: null })) || [];
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  get loaded() {
    return Array.isArray(this.runs);
  }

  get empty() {
    return this.loaded && !this.runs.length;
  }

  shown(run) {
    return {
      ...run,
      statusLabel: text(`Connector_Status_${run.status}`),
      statusTone: statusVariant(run.status),
      detail: text(
        'Connector_Runs_Detail',
        text(`Connector_StartedBy_${run.startedBy}`),
        text(runAsKey(run.ranAs)),
        run.version,
        run.recordsWritten
      ),
      nextAttempt:
        run.status === 'Waiting' && run.nextAttemptAt
          ? text('Connector_Runs_NextAttempt', new Date(run.nextAttemptAt).toLocaleString())
          : '',
      failure:
        run.status === 'Failed'
          ? text('Connector_Runs_Failure', run.failedStep || '-', run.errorMessage || '')
          : '',
      when: run.createdAt ? new Date(run.createdAt).toLocaleString() : '',
      canRetry: this.canManage && run.status === 'Failed',
      openId: `open-${run.id}`,
      nextId: `next-${run.id}`,
      retryId: `retry-${run.id}`
    };
  }

  get rows() {
    return (this.runs || []).map((run) => this.shown(run));
  }

  get openedRow() {
    return this.opened ? this.shown(this.opened) : undefined;
  }

  get openedSteps() {
    return this.opened ? stepRows(this.opened.stepLogJson, this.opened.resultsJson) : [];
  }

  async handleOpen(event) {
    const runId = event.target.dataset.run;
    await this.work(async () => {
      this.opened = await getRun({ runId });
    });
  }

  handleBack() {
    this.opened = undefined;
  }

  async handleRetry(event) {
    const runId = event.target.dataset.run;
    await this.work(async () => {
      const run = await retryRun({ runId });
      this.message = text('Connector_Runs_Retried', run.name);
      if (this.opened && this.opened.id === runId) {
        this.opened = run;
      }
      this.runs = (await getRuns({ recipeId: null })) || [];
    });
  }

  handleRefresh() {
    this.message = undefined;
    return this.load();
  }

  async work(call) {
    this.message = undefined;
    this.error = undefined;
    this.working = true;
    try {
      await call();
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  messageOf(failure) {
    return (failure && failure.body && failure.body.message) || text('Connector_Error_Unexpected');
  }
}
