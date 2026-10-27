import { LightningElement, api } from 'lwc';
import getTemplates from '@salesforce/apex/RollupTemplates.getTemplates';
import addRollups from '@salesforce/apex/RollupTemplates.addRollups';
import BUTTON from '@salesforce/label/c.Core_RollupEase_TplButton';
import INTRO from '@salesforce/label/c.Core_RollupEase_TplIntro';
import ADD from '@salesforce/label/c.Core_RollupEase_TplAdd';
import OPEN from '@salesforce/label/c.Core_RollupEase_TplOpen';
import CLOSE from '@salesforce/label/c.Core_RollupEase_TplClose';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Rollups_UnexpectedError';

/**
 * Starter Templates in the Rollup Builder (ease of use U2, ADR-0136). Opt-in only: nothing is
 * ticked, nothing is added until the administrator ticks rollups and clicks Add the Chosen
 * Rollups, and each is added switched off through the Builder's checks. Open in Builder opens
 * one prefilled, with Create a Field ready when its field is missing.
 *
 * Fires `open` with `detail.draft` (and the field to create), and `added` after an add.
 */
export default class RollupTemplates extends LightningElement {
  /** Only someone with Manage BarnCRM Settings sees the button. */
  @api canManage = false;

  labels = { button: BUTTON, intro: INTRO, add: ADD, open: OPEN, close: CLOSE };

  showing = false;
  templates;
  chosen = [];
  outcomes;
  error;
  busy = false;

  handleToggle() {
    this.showing = !this.showing;
    this.outcomes = undefined;
    // Read afresh on each opening: a field created or a rollup saved since changes the status.
    if (this.showing) {
      this.load();
    }
  }

  load() {
    this.error = undefined;
    return getTemplates()
      .then((result) => {
        this.templates = result || [];
      })
      .catch((error) => this.fail(error));
  }

  /** Each template with its rollups, ticked only where the administrator ticked them. */
  get templateList() {
    return (this.templates || []).map((template) => ({
      ...template,
      items: template.items.map((item) => ({
        ...item,
        id: `${template.key}.${item.key}`,
        checked: this.chosen.includes(`${template.key}.${item.key}`),
        disabled: !item.available
      }))
    }));
  }

  get nothingChosen() {
    return this.chosen.length === 0 || this.busy;
  }

  handleChoose(event) {
    const id = event.target.dataset.id;
    const others = this.chosen.filter((entry) => entry !== id);
    this.chosen = event.target.checked ? [...others, id] : others;
  }

  /** Adds the ticked rollups, switched off, one template at a time. */
  async handleAdd() {
    this.busy = true;
    this.error = undefined;
    const outcomes = [];
    try {
      for (const template of this.templates) {
        const itemKeys = this.chosen
          .filter((id) => id.startsWith(`${template.key}.`))
          .map((id) => id.substring(template.key.length + 1));
        if (itemKeys.length) {
          // eslint-disable-next-line no-await-in-loop
          const result = await addRollups({ templateKey: template.key, itemKeys });
          outcomes.push(...(result || []));
        }
      }
      this.outcomes = outcomes.map((outcome, index) => ({ ...outcome, key: String(index) }));
      this.chosen = [];
      this.templates = undefined;
      await this.load();
      this.dispatchEvent(new CustomEvent('added'));
    } catch (error) {
      this.fail(error);
    } finally {
      this.busy = false;
    }
  }

  handleOpen(event) {
    const [templateKey, itemKey] = event.target.dataset.id.split('.');
    const template = (this.templates || []).find((entry) => entry.key === templateKey);
    const item = template && template.items.find((entry) => entry.key === itemKey);
    if (!item) {
      return;
    }
    this.dispatchEvent(
      new CustomEvent('open', {
        detail: {
          draft: {
            ...item.draft,
            newFieldLabel: item.needsField ? item.fieldLabel : undefined,
            newFieldKind: item.needsField ? item.fieldKind : undefined
          }
        }
      })
    );
  }

  fail(error) {
    this.error = error && error.body && error.body.message ? error.body.message : UNEXPECTED_ERROR;
  }
}
