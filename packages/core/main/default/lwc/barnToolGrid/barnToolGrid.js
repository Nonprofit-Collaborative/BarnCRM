import { LightningElement, api } from 'lwc';

/**
 * A hub of tool tiles under short title-style group headings ("Bring Data In", "Find and
 * Change", "Careful"). Three tiles across on a wide screen, two on a tablet, one on a phone.
 *
 * groups: [{ name, label, tiles: [{ name, label, description, iconName, href, badgeLabel,
 * badgeVariant, disabled, disabledReason }] }]. A group with no tiles is left out. A tile's
 * `select` comes back out of the grid as `select` with `detail: { name }`.
 *
 * Group headings are h2, for a grid placed under a page shell's h1; a grid inside a card with
 * its own title should pass `heading-level="3"`.
 */
export default class BarnToolGrid extends LightningElement {
  @api groups = [];
  @api headingLevel = 2;

  get visibleGroups() {
    return (this.groups || [])
      .filter((group) => group && group.tiles && group.tiles.length)
      .map((group, index) => ({
        ...group,
        key: group.name || `group-${index}`,
        hasLabel: Boolean(group.label),
        tiles: group.tiles.map((tile, tileIndex) => ({
          ...tile,
          key: tile.name || `tile-${tileIndex}`,
          disabled: Boolean(tile.disabled)
        }))
      }));
  }

  handleSelect(event) {
    event.stopPropagation();
    this.dispatchEvent(new CustomEvent('select', { detail: { name: event.detail.name } }));
  }
}
