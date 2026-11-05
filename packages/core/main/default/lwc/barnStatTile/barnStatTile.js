import { LightningElement, api } from 'lwc';

const FORMAT_STYLES = {
  decimal: 'decimal',
  number: 'decimal',
  currency: 'currency',
  percent: 'percent'
};

/**
 * One figure as a big value over a short label, with an optional icon, status badge, border
 * and link, for example "12" over "Would Add", "$4,500" over "Open Asks" or "3" over
 * "Rejected" with an error badge. A number is formatted for the person's locale (thousands
 * separators, currency, percent); text (such as "More than 2,000") is shown as given.
 *
 * With `href` the whole tile is one link; with `clickable` it is one button that fires
 * `select` with `detail: { name }`. Rows of tiles: `slds-grid slds-wrap slds-gutters_x-small`
 * with each tile in `slds-col slds-size_1-of-2 slds-medium-size_1-of-4`, `bordered` and
 * `align="start"`; centered without a border stays the default for a single hero figure.
 */
export default class BarnStatTile extends LightningElement {
  @api label;
  /** A number, or text when the figure is not exact. */
  @api value;
  /** "decimal" (default), "currency" or "percent" (0.25 shows as 25%). */
  @api formatStyle;
  /** ISO currency code for "currency"; the person's currency when empty. */
  @api currencyCode;
  /** A small icon left of the label, from c/barnIcons where it names a tab or object. */
  @api iconName;
  @api badgeLabel;
  /** A status word from the vocabulary (c/barnStatus), for example "success" or "overdue". */
  @api badgeVariant;
  /** "center" (default) or "start" for a row of tiles. */
  @api align;
  /** A hook-based border and radius, matching c-barn-tool-tile. */
  @api bordered = false;
  /** Makes the tile one link. */
  @api href;
  /** Makes the tile one button that fires `select`. */
  @api clickable = false;
  /** The value `select` carries. */
  @api name;

  get isNumber() {
    return typeof this.value === 'number';
  }

  get numberStyle() {
    return FORMAT_STYLES[this.formatStyle] || 'decimal';
  }

  get hasBadge() {
    return Boolean(this.badgeLabel);
  }

  get isLink() {
    return Boolean(this.href);
  }

  get isButton() {
    return !this.href && this.clickable;
  }

  get tileClass() {
    const classes = ['stat'];
    if (this.align === 'start') {
      classes.push('stat_start');
    }
    if (this.bordered) {
      classes.push('stat_bordered');
    }
    if (this.isLink || this.isButton) {
      classes.push('stat_action');
    }
    return classes.join(' ');
  }

  handleSelect() {
    this.dispatchEvent(new CustomEvent('select', { detail: { name: this.name } }));
  }
}
