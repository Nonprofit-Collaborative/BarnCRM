import { LightningElement, api } from 'lwc';
import { parseQueryText, PROBLEMS } from 'c/findQueryText';

import TYPE_QUERY from '@salesforce/label/c.Core_Find_TypeQuery';
import QUERY_TEXT from '@salesforce/label/c.Core_Find_QueryText';
import USE_QUERY from '@salesforce/label/c.Core_Find_UseQuery';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const MESSAGE_BY_PROBLEM = () => ({
  [PROBLEMS.SYNTAX]: helpText('Core', 'Core_Find_TextSyntax'),
  [PROBLEMS.MIXED_LOGIC]: helpText('Core', 'Core_Find_TextMixed'),
  [PROBLEMS.LIKE]: helpText('Core', 'Core_Find_TextLike'),
  [PROBLEMS.RELATED_PLACE]: helpText('Core', 'Core_Find_TextRelated'),
  [PROBLEMS.UNSUPPORTED]: helpText('Core', 'Core_Find_TextUnsupported'),
  [PROBLEMS.ONE_SORT]: helpText('Core', 'Core_Find_TextOneSort'),
  [PROBLEMS.EMPTY]: helpText('Core', 'Core_Find_TextEmpty')
});

/**
 * Typing a Find query (C-36, admin guide find.md section 7.4, canonical model R-SQ7). The text
 * is read into a query document here, in the browser, and handed to findRecords in an `apply`
 * event, which loads it into the builder. The text is never sent to the server.
 */
export default class FindQueryTextPanel extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  /** The SOQL Find shows for the current query; the text box starts with it. */
  @api soql = '';
  @api disabled = false;

  labels = {
    typeQuery: TYPE_QUERY,
    queryText: QUERY_TEXT,
    get queryTextHelp() {
      return helpText('Core', 'Core_Find_QueryTextHelp');
    },
    useQuery: USE_QUERY
  };

  open = false;
  text = '';
  errorMessage;

  get expanded() {
    return String(this.open);
  }

  get hasError() {
    return !!this.errorMessage;
  }

  handleToggle() {
    this.open = !this.open;
    if (this.open) {
      this.text = this.soql || '';
      this.errorMessage = undefined;
    }
  }

  handleTextChange(event) {
    this.text = event.target.value;
  }

  handleUse() {
    let document;
    try {
      document = parseQueryText(this.text);
    } catch (error) {
      const template =
        MESSAGE_BY_PROBLEM()[error.problem] || helpText('Core', 'Core_Find_TextSyntax');
      this.errorMessage = template.split('{0}').join(error.near || '');
      return;
    }
    this.errorMessage = undefined;
    this.open = false;
    this.dispatchEvent(new CustomEvent('apply', { detail: { document } }));
  }
}
