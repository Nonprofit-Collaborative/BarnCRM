/**
 * Volunteers Home's view logic in plain JavaScript (plan 9.9): the figures as the page shows
 * them, and where each one goes. No lightning or @salesforce imports, so the same logic serves
 * BarnCRM for WordPress.
 */

/** A figure's badge keeps its status color only while there is something to act on. */
export function badgeStatusFor(tile) {
  if (!tile || !tile.badgeLabel) {
    return undefined;
  }
  return tile.value > 0 ? tile.badgeStatus : 'neutral';
}

/** The value a figure shows: the number, or the cap with a plus when there are more. */
export function valueFor(tile, locale) {
  const value = tile && Number.isFinite(tile.value) ? tile.value : 0;
  if (tile && tile.capped) {
    return `${new Intl.NumberFormat(locale).format(value)}+`;
  }
  if (tile && tile.currencyCode) {
    return new Intl.NumberFormat(locale, { style: 'currency', currency: tile.currencyCode }).format(
      value
    );
  }
  return value;
}

/** Where a figure goes: its app page tab, or its object's list view. */
export function pageReferenceFor(tile) {
  if (!tile) {
    return null;
  }
  if (tile.tabName) {
    return { type: 'standard__navItemPage', attributes: { apiName: tile.tabName } };
  }
  return {
    type: 'standard__objectPage',
    attributes: { objectApiName: tile.objectApiName, actionName: 'list' },
    state: { filterName: tile.filterName || 'Recent' }
  };
}

/** The figures as `c-barn-stat-tile` takes them. `iconFor` maps a tab or object to its icon. */
export function toTiles(tiles, iconFor, locale) {
  return (tiles || []).map((tile) => ({
    name: tile.name,
    label: tile.label,
    value: valueFor(tile, locale),
    badgeLabel: tile.badgeLabel,
    badgeVariant: badgeStatusFor(tile),
    iconName: iconFor ? iconFor(tile.tabName || tile.objectApiName) : undefined
  }));
}
