/**
 * Reads a typed Find query into the query document (C-36, canonical model R-SQ7, ADR-NEXT
 * `NEXT-typed-find-queries-are-parsed-into-the-query-document.md`).
 *
 * The text is a subset of SOQL: exactly what the document can hold, and nothing else. The
 * result is a document like the one the builder writes, which Find loads into the builder and
 * sends to the server; the text itself is never sent. The server checks the document as it
 * checks any other (R-SQ2), so this module only has to be faithful, not trusted.
 *
 * It also reads back the SOQL Find displays for a document, so a person can switch between the
 * builder and text.
 */

export const PROBLEMS = Object.freeze({
  SYNTAX: 'syntax',
  MIXED_LOGIC: 'mixedLogic',
  LIKE: 'like',
  RELATED_PLACE: 'relatedPlace',
  UNSUPPORTED: 'unsupported',
  ONE_SORT: 'oneSort',
  EMPTY: 'empty'
});

/** Why a text could not be read: a problem key and the words it stopped at. */
export class QueryTextError extends Error {
  constructor(problem, near) {
    super(problem);
    this.problem = problem;
    this.near = near || '';
  }
}

const COMPARISON_BY_OPERATOR = {
  '=': 'equals',
  '!=': 'not equals',
  '<>': 'not equals',
  '<': 'less than',
  '<=': 'less or equal',
  '>': 'greater than',
  '>=': 'greater or equal'
};
const UNSUPPORTED_WORDS = new Set([
  'GROUP',
  'HAVING',
  'OFFSET',
  'WITH',
  'FOR',
  'USING',
  'TYPEOF',
  'INCLUDES',
  'EXCLUDES'
]);

// -----------------------------------------------------------------------------------------
// Tokens
// -----------------------------------------------------------------------------------------

const TOKEN_PATTERNS = [
  ['space', /^\s+/],
  ['string', /^'(?:[^'\\]|\\.)*'/],
  ['datetime', /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z/],
  ['date', /^\d{4}-\d{2}-\d{2}(?![\d:T])/],
  ['number', /^-?\d+(?:\.\d+)?(?![\w.])/],
  ['word', /^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*(?::\d+)?/],
  ['op', /^(?:<>|!=|<=|>=|=|<|>)/],
  ['punct', /^[(),]/]
];

/** The first token at the start of `text`, as [type, match], or null. */
function nextToken(text) {
  for (const [type, pattern] of TOKEN_PATTERNS) {
    const match = pattern.exec(text);
    if (match) {
      return [type, match];
    }
  }
  return null;
}

function tokenize(text) {
  const tokens = [];
  let rest = String(text || '');
  while (rest.length > 0) {
    const found = nextToken(rest);
    if (!found) {
      throw new QueryTextError(PROBLEMS.SYNTAX, rest.slice(0, 20));
    }
    const [type, match] = found;
    if (type !== 'space') {
      tokens.push({ type, text: match[0], upper: match[0].toUpperCase() });
    }
    rest = rest.slice(match[0].length);
  }
  return tokens;
}

const ESCAPES = { n: '\n', t: '\t', r: '\r', "'": "'", '"': '"', '\\': '\\' };

/**
 * The text of a quoted string, with its backslash escapes read. `\%` and `\_` are kept as they
 * are, because they mean something only to LIKE, which reads them itself.
 */
function unquote(text) {
  return text.slice(1, -1).replace(/\\(.)/g, (whole, character) => {
    return ESCAPES[character] !== undefined ? ESCAPES[character] : whole;
  });
}

// -----------------------------------------------------------------------------------------
// The parser
// -----------------------------------------------------------------------------------------

class Parser {
  constructor(tokens) {
    this.tokens = tokens;
    this.at = 0;
  }

  peek(offset = 0) {
    return this.tokens[this.at + offset];
  }

  near() {
    return this.tokens
      .slice(this.at, this.at + 4)
      .map((token) => token.text)
      .join(' ');
  }

  fail(problem = PROBLEMS.SYNTAX) {
    throw new QueryTextError(problem, this.near());
  }

  isWord(upper, offset = 0) {
    const token = this.peek(offset);
    return !!token && token.type === 'word' && token.upper === upper;
  }

  isPunct(text, offset = 0) {
    const token = this.peek(offset);
    return !!token && token.type === 'punct' && token.text === text;
  }

  take() {
    const token = this.peek();
    if (!token) {
      this.fail();
    }
    this.at++;
    return token;
  }

  expectWord(upper) {
    if (!this.isWord(upper)) {
      this.fail();
    }
    return this.take();
  }

  expectPunct(text) {
    if (!this.isPunct(text)) {
      this.fail();
    }
    return this.take();
  }

  /** A field path or name; refuses keywords that this subset does not read. */
  name() {
    const token = this.peek();
    if (!token || token.type !== 'word' || token.text.includes(':')) {
      this.fail();
    }
    if (UNSUPPORTED_WORDS.has(token.upper)) {
      this.fail(PROBLEMS.UNSUPPORTED);
    }
    this.at++;
    if (this.isPunct('(')) {
      // A function such as COUNT(Id) or toLabel(Status).
      this.at--;
      this.fail(PROBLEMS.UNSUPPORTED);
    }
    return token.text;
  }

  /** The whole query: SELECT ... FROM ... [WHERE] [ORDER BY] [LIMIT]. */
  query() {
    if (this.tokens.length === 0) {
      throw new QueryTextError(PROBLEMS.EMPTY, '');
    }
    this.expectWord('SELECT');
    const fields = [];
    const children = [];
    do {
      if (this.isPunct('(')) {
        children.push(this.childColumn());
      } else {
        fields.push(this.name());
      }
    } while (this.isPunct(',') && this.take());
    this.expectWord('FROM');
    const document = { version: 1, object: this.name(), fields: withoutId(fields) };
    if (children.length > 0) {
      document.children = children;
    }
    if (this.isWord('WHERE')) {
      this.take();
      const { filter, related } = this.where(true);
      if (filter) {
        document.filter = filter;
      }
      if (related.length > 0) {
        document.related = related;
      }
    }
    const order = this.orderBy();
    if (order) {
      document.orderBy = [order];
    }
    const limit = this.limit();
    if (limit !== undefined) {
      document.limit = limit;
    }
    if (this.peek()) {
      this.fail(UNSUPPORTED_WORDS.has(this.peek().upper) ? PROBLEMS.UNSUPPORTED : PROBLEMS.SYNTAX);
    }
    return document;
  }

  /** `(SELECT fields FROM Relationship [ORDER BY ...] [LIMIT n])`, a related record column. */
  childColumn() {
    this.expectPunct('(');
    this.expectWord('SELECT');
    const fields = [];
    do {
      fields.push(this.name());
    } while (this.isPunct(',') && this.take());
    this.expectWord('FROM');
    const column = { relationship: this.name(), fields: withoutId(fields) };
    // Find always lists the newest related records first, so a sort here changes nothing.
    this.orderBy();
    const limit = this.limit();
    if (limit !== undefined) {
      column.limit = limit;
    }
    this.expectPunct(')');
    return column;
  }

  orderBy() {
    if (!this.isWord('ORDER')) {
      return undefined;
    }
    this.take();
    this.expectWord('BY');
    const order = { field: this.name(), direction: 'ASC' };
    if (this.isWord('ASC') || this.isWord('DESC')) {
      order.direction = this.take().upper;
    }
    if (this.isWord('NULLS')) {
      // Find sorts blanks first going up and last going down; the words are read and kept so.
      this.take();
      if (!this.isWord('FIRST') && !this.isWord('LAST')) {
        this.fail();
      }
      this.take();
    }
    if (this.isPunct(',')) {
      this.fail(PROBLEMS.ONE_SORT);
    }
    return order;
  }

  limit() {
    if (!this.isWord('LIMIT')) {
      return undefined;
    }
    this.take();
    const token = this.take();
    if (token.type !== 'number' || !/^\d+$/.test(token.text)) {
      this.at--;
      this.fail();
    }
    return Number(token.text);
  }

  /** The WHERE expression as a filter document, and related records when they may appear. */
  where(allowRelated) {
    const tree = this.orExpression(allowRelated);
    const items = flattenAnd(tree);
    const related = items.filter((item) => item.type === 'related').map((item) => item.entry);
    const rest = items.filter((item) => item.type !== 'related');
    if (rest.some(containsRelated)) {
      throw new QueryTextError(PROBLEMS.RELATED_PLACE, 'Id IN (SELECT');
    }
    return { filter: toFilter(rest), related };
  }

  orExpression(allowRelated) {
    const first = this.andExpression(allowRelated);
    if (!this.isWord('OR')) {
      return first.node;
    }
    const items = [first];
    while (this.isWord('OR')) {
      this.take();
      items.push(this.andExpression(allowRelated));
    }
    if (items.some((item) => item.bare)) {
      throw new QueryTextError(PROBLEMS.MIXED_LOGIC, 'AND ... OR');
    }
    return { type: 'or', items: items.map((item) => item.node) };
  }

  /** An AND chain; `bare` says it has more than one item and no brackets of its own. */
  andExpression(allowRelated) {
    const items = [this.unary(allowRelated)];
    while (this.isWord('AND')) {
      this.take();
      items.push(this.unary(allowRelated));
    }
    return items.length === 1
      ? { node: items[0], bare: false }
      : { node: { type: 'and', items }, bare: true };
  }

  unary(allowRelated) {
    if (this.isWord('NOT') && !this.isWord('IN', 1)) {
      this.take();
      return { type: 'not', item: this.unary(allowRelated) };
    }
    if (this.isPunct('(')) {
      this.take();
      const item = this.orExpression(allowRelated);
      this.expectPunct(')');
      return { type: 'group', item };
    }
    return this.term(allowRelated);
  }

  /** One comparison, or `Id [NOT] IN (SELECT ...)` for related records. */
  term(allowRelated) {
    const field = this.name();
    if (this.isWord('LIKE')) {
      this.take();
      const token = this.take();
      if (token.type !== 'string') {
        this.at--;
        this.fail();
      }
      return { type: 'term', condition: likeCondition(field, unquote(token.text)) };
    }
    let negated = false;
    if (this.isWord('NOT') && this.isWord('IN', 1)) {
      this.take();
      negated = true;
    }
    if (this.isWord('IN')) {
      this.take();
      this.expectPunct('(');
      if (this.isWord('SELECT')) {
        if (!allowRelated || field.toUpperCase() !== 'ID') {
          this.fail(PROBLEMS.RELATED_PLACE);
        }
        return { type: 'related', entry: this.relatedRecords(!negated) };
      }
      const values = [];
      do {
        values.push(this.value());
      } while (this.isPunct(',') && this.take());
      this.expectPunct(')');
      return {
        type: 'term',
        condition: { field, operator: negated ? 'not in' : 'in', value: values }
      };
    }
    if (negated) {
      this.fail();
    }
    const operatorToken = this.take();
    if (operatorToken.type !== 'op') {
      this.at--;
      this.fail(
        UNSUPPORTED_WORDS.has(operatorToken.upper) ? PROBLEMS.UNSUPPORTED : PROBLEMS.SYNTAX
      );
    }
    return { type: 'term', condition: this.comparison(field, operatorToken.text) };
  }

  comparison(field, operatorText) {
    const operator = COMPARISON_BY_OPERATOR[operatorText];
    const token = this.peek();
    if (token && token.type === 'word') {
      const relative = relativeDate(token.upper);
      if (token.upper === 'NULL' && (operator === 'equals' || operator === 'not equals')) {
        this.take();
        return { field, operator: operator === 'equals' ? 'is null' : 'is not null' };
      }
      if (relative && operator === 'equals') {
        this.take();
        return { field, ...relative };
      }
      if (relative || token.upper === 'NULL') {
        this.fail(PROBLEMS.UNSUPPORTED);
      }
    }
    return { field, operator, value: this.value() };
  }

  /** A literal: text, a number, a date, a date and time, or TRUE or FALSE. */
  value() {
    const token = this.take();
    switch (token.type) {
      case 'string':
        return unquote(token.text);
      case 'number':
        return Number(token.text);
      case 'date':
      case 'datetime':
        return token.text;
      case 'word':
        if (token.upper === 'TRUE' || token.upper === 'FALSE') {
          return token.upper === 'TRUE';
        }
        break;
      default:
        break;
    }
    this.at--;
    return this.fail();
  }

  /** `SELECT lookup FROM Child [WHERE ...])`, after `Id [NOT] IN (`. */
  relatedRecords(has) {
    this.expectWord('SELECT');
    const field = this.name();
    this.expectWord('FROM');
    const entry = { object: this.name(), field, has };
    if (this.isWord('WHERE')) {
      this.take();
      const { filter } = this.where(false);
      if (filter) {
        entry.filter = filter;
      }
    }
    this.expectPunct(')');
    return entry;
  }
}

// -----------------------------------------------------------------------------------------
// From the tree to the document
// -----------------------------------------------------------------------------------------

function withoutId(fields) {
  const others = fields.filter((field) => field.toUpperCase() !== 'ID');
  return others.length > 0 ? others : fields;
}

function relativeDate(upper) {
  if (upper === 'THIS_YEAR') {
    return { operator: 'this year' };
  }
  if (upper === 'LAST_YEAR') {
    return { operator: 'last year' };
  }
  const days = /^LAST_N_DAYS:(\d+)$/.exec(upper);
  return days ? { operator: 'last n days', value: Number(days[1]) } : null;
}

/**
 * `LIKE` as the document has it: `'text%'` starts with, `'%text%'` contains, and text with no
 * wildcard equals. `\%` and `\_` are the characters themselves.
 */
function likeCondition(field, pattern) {
  const parts = [];
  let text = '';
  for (let i = 0; i < pattern.length; i++) {
    const character = pattern[i];
    if (character === '\\' && i + 1 < pattern.length) {
      text += pattern[++i];
    } else if (character === '%') {
      parts.push(text, '%');
      text = '';
    } else if (character === '_') {
      throw new QueryTextError(PROBLEMS.LIKE, `'${pattern}'`);
    } else {
      text += character;
    }
  }
  parts.push(text);
  const shape = parts.map((part) => (part === '%' ? '%' : part === '' ? '' : 'x')).join('');
  const words = parts.filter((part) => part !== '%' && part !== '');
  if (shape === 'x') {
    return { field, operator: 'equals', value: words[0] };
  }
  if (shape === 'x%') {
    return { field, operator: 'starts with', value: words[0] };
  }
  if (shape === '%x%') {
    return { field, operator: 'contains', value: words[0] };
  }
  throw new QueryTextError(PROBLEMS.LIKE, `'${pattern}'`);
}

/** The items of the top-level AND, through brackets, since AND does not care about them. */
function flattenAnd(node) {
  if (node.type === 'and') {
    return node.items.flatMap(flattenAnd);
  }
  if (node.type === 'group' && node.item.type !== 'or' && node.item.type !== 'not') {
    return flattenAnd(node.item);
  }
  return [node];
}

function containsRelated(node) {
  if (node.type === 'related') {
    return true;
  }
  if (node.items) {
    return node.items.some(containsRelated);
  }
  return node.item ? containsRelated(node.item) : false;
}

/** An R-R2 filter document from the top-level items, numbering conditions as they appear. */
function toFilter(items) {
  if (items.length === 0) {
    return undefined;
  }
  const conditions = [];
  const render = (node) => {
    switch (node.type) {
      case 'term':
        conditions.push(node.condition);
        return String(conditions.length);
      case 'and':
        return node.items.map(render).join(' AND ');
      case 'or':
        return node.items.map(render).join(' OR ');
      case 'not':
        return `NOT ${render(node.item)}`;
      default: {
        // Brackets around one condition, or around NOT and one thing, say nothing; drop them.
        let inner = node.item;
        while (inner.type === 'group') {
          inner = inner.item;
        }
        return inner.type === 'term' || inner.type === 'not' ? render(inner) : `(${render(inner)})`;
      }
    }
  };
  const logic = items.map(render).join(' AND ');
  const filter = { version: 1 };
  if (!items.every((item) => item.type === 'term')) {
    filter.logic = logic;
  }
  filter.conditions = conditions.map((condition, index) => ({ id: index + 1, ...condition }));
  return filter;
}

/**
 * Reads typed text into a query document, or throws a QueryTextError whose `problem` is one
 * of PROBLEMS and whose `near` is the words it stopped at.
 */
export function parseQueryText(text) {
  return new Parser(tokenize(text)).query();
}
