/**
 * Project billing and financials logic with no framework (PM-10, PM-11; plan Section 9.9): the
 * default invoice period, the invoice CSV rows, and the Financials card's margin, unbilled and
 * month table with the open month (R-PM21). Plain functions on plain data, so the same code can
 * run outside Salesforce.
 */

const num = (value) => (typeof value === 'number' && !Number.isNaN(value) ? value : 0);
const round = (value) => Math.round(value * 100) / 100;
const iso = (day) =>
  `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;

/** Last calendar month, the usual invoice period: `{ start, end }` as YYYY-MM-DD. */
export function defaultPeriod(today = new Date()) {
  const start = new Date(today.getFullYear(), today.getMonth() - 1, 1);
  const end = new Date(today.getFullYear(), today.getMonth(), 0);
  return { start: iso(start), end: iso(end) };
}

/** The first day of the month before `today`, as YYYY-MM-DD (Recognize Revenue's default). */
export function lastClosedMonth(today = new Date()) {
  return defaultPeriod(today).start;
}

/** The invoice export's columns, for `c/findCsv`'s `toCsv`. */
export const INVOICE_COLUMNS = [
  { label: 'Invoice', path: 'invoice' },
  { label: 'Status', path: 'status' },
  { label: 'Project', path: 'project' },
  { label: 'Client', path: 'client' },
  { label: 'Invoice Date', path: 'invoiceDate' },
  { label: 'Due Date', path: 'dueDate' },
  { label: 'Paid Date', path: 'paidDate' },
  { label: 'Invoice Total', path: 'total' },
  { label: 'Amount Paid', path: 'amountPaid' },
  { label: 'Line Type', path: 'lineType' },
  { label: 'Description', path: 'description' },
  { label: 'Service Date', path: 'serviceDate' },
  { label: 'Quantity', path: 'quantity' },
  { label: 'Unit Price', path: 'unitPrice' },
  { label: 'Amount', path: 'amount' }
];

/** One CSV row per invoice line, each with its invoice's columns; an invoice with none gets one. */
export function invoiceRows(invoices) {
  const rows = [];
  for (const invoice of invoices || []) {
    const { lines, name, ...rest } = invoice;
    const head = { invoice: name, ...rest };
    if (!lines || !lines.length) {
      rows.push(head);
    }
    for (const line of lines || []) {
      rows.push({ ...head, ...line });
    }
  }
  return rows;
}

/**
 * The card's derived figures (R-PM21): margin and margin percent (with cost only), unbilled,
 * and the month table: the stored months, then the open month as revenue (and cost) to date
 * less everything stored.
 */
export function financials(card, today = new Date()) {
  const revenue = num(card?.revenue);
  const withCost = card?.withCost === true;
  const cost = num(card?.cost);
  const months = (card?.months || []).map((row) => ({
    key: row.month,
    month: row.month,
    recognized: num(row.recognized),
    cost: withCost ? num(row.cost) : null,
    open: false
  }));
  const stored = months.reduce((sum, row) => sum + row.recognized, 0);
  const storedCost = months.reduce((sum, row) => sum + num(row.cost), 0);
  const thisMonth = iso(new Date(today.getFullYear(), today.getMonth(), 1));
  months.push({
    key: 'open',
    month: thisMonth,
    recognized: round(revenue - stored),
    cost: withCost ? round(cost - storedCost) : null,
    open: true
  });
  const margin = withCost ? round(revenue - cost) : null;
  return {
    budget: card?.budget ?? null,
    revenue: round(revenue),
    cost: withCost ? round(cost) : null,
    margin,
    marginPercent: withCost && revenue ? Math.round((margin / revenue) * 100) : null,
    invoiced: round(num(card?.invoiced)),
    unbilled: round(revenue - num(card?.invoiced)),
    months
  };
}
