/**
 * Turns the cards modules return (RecordGlanceController) into what the glance card draws.
 * Framework free, so it ports with the rest of the record page logic (plan 9.9).
 */
import { formatDate } from 'c/barnFormat';

/** One tile's value and format for c-barn-stat-tile: a number keeps its number, a date is text. */
export function tileView(tile, index, locale) {
  const view = {
    key: `${index}-${tile.label}`,
    label: tile.label,
    value: null,
    formatStyle: undefined
  };
  if (tile.kind === 'currency' || tile.kind === 'number') {
    view.value =
      tile.numberValue === null || tile.numberValue === undefined ? null : Number(tile.numberValue);
    view.formatStyle = tile.kind === 'currency' ? 'currency' : 'decimal';
  } else if (tile.kind === 'date') {
    view.value = formatDate(tile.dateValue, locale);
  } else {
    view.value = tile.textValue || null;
  }
  return view;
}

/** A date as the person's locale writes it, from the shared kit. */
export { formatDate };

/** The cards ready to draw: tiles without a value are left out, and actions keep their page reference. */
export function cardViews(cards, locale) {
  return (cards || []).map((card) => ({
    key: card.key || card.title,
    title: card.title,
    iconName: card.iconName,
    tiles: (card.tiles || [])
      .map((tile, index) => tileView(tile, index, locale))
      .filter((tile) => tile.value !== null && tile.value !== ''),
    actions: (card.actions || []).map((action, index) => ({
      key: `${index}-${action.label}`,
      label: action.label,
      pageReference: parseReference(action.pageReference)
    }))
  }));
}

function parseReference(json) {
  try {
    return json ? JSON.parse(json) : null;
  } catch {
    return null;
  }
}
