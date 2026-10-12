import { LightningElement, api } from 'lwc';
import { parseQueryText, PROBLEMS } from 'c/findQueryText';

import TYPE_QUERY from '@salesforce/label/c.Core_Find_TypeQuery';
import QUERY_TEXT from '@salesforce/label/c.Core_Find_QueryText';
import QUERY_TEXT_HELP from '@salesforce/label/c.Core_Find_QueryTextHelp';
import USE_QUERY from '@salesforce/label/c.Core_Find_UseQuery';
import TEXT_SYNTAX from '@salesforce/label/c.Core_Find_TextSyntax';
import TEXT_MIXED from '@salesforce/label/c.Core_Find_TextMixed';
import TEXT_LIKE from '@salesforce/label/c.Core_Find_TextLike';
import TEXT_RELATED from '@salesforce/label/c.Core_Find_TextRelated';
import TEXT_UNSUPPORTED from '@salesforce/label/c.Core_Find_TextUnsupported';
import TEXT_ONE_SORT from '@salesforce/label/c.Core_Find_TextOneSort';
import TEXT_EMPTY from '@salesforce/label/c.Core_Find_TextEmpty';

const MESSAGE_BY_PROBLEM = {
  [PROBLEMS.SYNTAX]: TEXT_SYNTAX,
  [PROBLEMS.MIXED_LOGIC]: TEXT_MIXED,
  [PROBLEMS.LIKE]: TEXT_LIKE,
  [PROBLEMS.RELATED_PLACE]: TEXT_RELATED,
  [PROBLEMS.UNSUPPORTED]: TEXT_UNSUPPORTED,
  [PROBLEMS.ONE_SORT]: TEXT_ONE_SORT,
  [PROBLEMS.EMPTY]: TEXT_EMPTY
};

/**
 * Typing a Find query (C-36, admin guide find.md section 7.4, canonical model R-SQ7). The text
 * is read into a query document here, in the browser, and handed to findRecords in an `apply`
 * event, which loads it into the builder. The text is never sent to the server.
 */
export default class FindQueryTextPanel extends LightningElement {
  /** The SOQL Find shows for the current query; the text box starts with it. */
  @api soql = '';
  @api disabled = false;

  labels = {
    typeQuery: TYPE_QUERY,
    queryText: QUERY_TEXT,
    queryTextHelp: QUERY_TEXT_HELP,
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
      const template = MESSAGE_BY_PROBLEM[error.problem] || TEXT_SYNTAX;
      this.errorMessage = template.split('{0}').join(error.near || '');
      return;
    }
    this.errorMessage = undefined;
    this.open = false;
    this.dispatchEvent(new CustomEvent('apply', { detail: { document } }));
  }
}
