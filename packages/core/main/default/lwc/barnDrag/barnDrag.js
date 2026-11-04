/**
 * Drag and drop for lists, boards and diagrams (v1.0 visual standard). Framework free (plan
 * 9.9): it uses only DOM pointer, keyboard and geometry APIs, so it ports as is.
 *
 * Drag and drop is always an addition. The screen keeps its own Move Up / Move Down buttons or
 * menu; this adds a pointer drag (mouse, pen, and touch after a short press and hold) and a
 * keyboard drag (Space picks up, the arrow keys move, Space or Enter drops, Escape cancels),
 * and announces every step through the caller's aria-live region.
 *
 * Markup the caller writes:
 *   - a drop zone: any element with data-drop-zone="<zone id>" and data-drop-label="<name>"
 *     (a board column, a list, or for "drag onto a part" each part itself);
 *   - a draggable item inside a zone: data-drag-id="<item id>", data-drag-label="<name>",
 *     tabindex="0", onpointerdown and onkeydown handlers that call the controller.
 *
 *   import { createDragController } from 'c/barnDrag';
 *   import { dragMessages } from 'c/barnDragText';
 *   this.drag = createDragController({
 *     root: this.template,
 *     layout: 'columns',                     // 'columns' (zones side by side) or 'list'
 *     messages: dragMessages(),              // after loadHelp([... , 'Core'])
 *     announce: (text) => { this.liveText = text; },
 *     onChange: (state) => { this.dragState = state; },   // highlight source and target
 *     onDrop: ({ itemId, fromZone, toZone, toIndex }) => this.move(...)  // false = snap back
 *   });
 *   handlePointerDown(event) { this.drag.pointerDown(event); }
 *   handleDragKey(event) { this.drag.keyDown(event); }
 *   disconnectedCallback() { this.drag.destroy(); }
 *
 * State given to onChange: { active, mode ('pointer' or 'keyboard'), itemId, fromZone,
 * fromIndex, overZone, overIndex, x, y }. overIndex is the insertion position among the target
 * zone's items, not counting the dragged item.
 */

const HOLD_MS = 250; // touch: press and hold before a drag starts, so a swipe still scrolls
const MOUSE_SLOP = 4; // mouse or pen: pixels of movement that turn a press into a drag
const TOUCH_SLOP = 8; // touch: movement before the hold ends means the person is scrolling

const IDLE = Object.freeze({
  active: false,
  mode: null,
  itemId: null,
  fromZone: null,
  fromIndex: -1,
  overZone: null,
  overIndex: -1,
  x: 0,
  y: 0
});

function noop() {}

function format(template, args) {
  return String(template || '').replace(/\{(\d+)\}/g, (match, n) => {
    const value = args[Number(n)];
    return value === undefined || value === null ? '' : String(value);
  });
}

function message(messages, name, ...args) {
  const entry = messages && messages[name];
  if (typeof entry === 'function') {
    return entry(...args);
  }
  return format(entry, args);
}

function rectOf(element) {
  return element && typeof element.getBoundingClientRect === 'function'
    ? element.getBoundingClientRect()
    : { left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0 };
}

function contains(rect, x, y) {
  return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
}

/**
 * Creates a controller. Options: root (has querySelectorAll; the component's template), layout,
 * messages ({ pickedUp, position, dropped, cancelled }: strings with {0} or functions), announce,
 * onChange, onDrop, canDrop(itemId, fromZone, toZone) (optional; a refused zone is skipped by
 * the keyboard and ignored by the pointer), zoneSelector, itemSelector, holdMs.
 */
export function createDragController(options = {}) {
  const root = options.root;
  const layout = options.layout === 'list' ? 'list' : 'columns';
  const zoneSelector = options.zoneSelector || '[data-drop-zone]';
  const itemSelector = options.itemSelector || '[data-drag-id]';
  const holdMs = options.holdMs === undefined ? HOLD_MS : options.holdMs;
  const announce = options.announce || noop;
  const onChange = options.onChange || noop;
  const onDrop = options.onDrop || noop;
  const canDrop = options.canDrop || (() => true);
  const messages = options.messages || {};

  let state = IDLE;
  let pending = null; // a pointer press that has not become a drag yet
  let holdTimer = null;
  let listening = false;
  let busy = false;

  // ---- geometry -------------------------------------------------------------------------

  function zones() {
    if (!root || typeof root.querySelectorAll !== 'function') {
      return [];
    }
    return Array.from(root.querySelectorAll(zoneSelector)).map((element) => {
      const items = Array.from(element.querySelectorAll(itemSelector)).filter(
        // An item belongs to the innermost zone that holds it (a part that is also a zone).
        (item) => item !== element
      );
      return {
        id: element.dataset.dropZone,
        label: element.dataset.dropLabel || '',
        element,
        items: items.map((item) => ({ id: item.dataset.dragId, element: item }))
      };
    });
  }

  function zoneOfItem(all, itemId) {
    for (const zone of all) {
      const index = zone.items.findIndex((item) => item.id === itemId);
      if (index >= 0) {
        return { zone, index };
      }
    }
    return { zone: null, index: -1 };
  }

  function others(zone, itemId) {
    return zone ? zone.items.filter((item) => item.id !== itemId) : [];
  }

  function labelOfItem(itemId) {
    const all = zones();
    const found = zoneOfItem(all, itemId).zone;
    const item = found && found.items.find((entry) => entry.id === itemId);
    return item ? item.element.dataset.dragLabel || '' : '';
  }

  function zoneLabel(zoneId) {
    const zone = zones().find((entry) => entry.id === zoneId);
    return zone ? zone.label : '';
  }

  // The innermost zone under the point (a part inside a column wins over the column).
  function zoneAt(all, x, y) {
    let best = null;
    all.forEach((zone) => {
      if (contains(rectOf(zone.element), x, y)) {
        if (!best || best.element.contains(zone.element)) {
          best = zone;
        }
      }
    });
    return best;
  }

  function indexAt(zone, itemId, x, y) {
    const rest = others(zone, itemId);
    for (let i = 0; i < rest.length; i++) {
      const rect = rectOf(rest[i].element);
      const middle = rect.top + rect.height / 2;
      if (y < middle) {
        return i;
      }
    }
    return rest.length;
  }

  // ---- state ----------------------------------------------------------------------------

  function setState(next) {
    state = Object.freeze({ ...state, ...next });
    onChange(state);
  }

  function reset() {
    state = IDLE;
    onChange(state);
  }

  function announcePosition() {
    const all = zones();
    const zone = all.find((entry) => entry.id === state.overZone);
    const count = others(zone, state.itemId).length + 1;
    announce(message(messages, 'position', zone ? zone.label : '', state.overIndex + 1, count));
  }

  function start(mode, itemId, x, y) {
    const all = zones();
    const { zone, index } = zoneOfItem(all, itemId);
    if (!zone) {
      return false;
    }
    setState({
      active: true,
      mode,
      itemId,
      fromZone: zone.id,
      fromIndex: index,
      overZone: zone.id,
      overIndex: index,
      x,
      y
    });
    announce(message(messages, 'pickedUp', labelOfItem(itemId)));
    return true;
  }

  function cancel() {
    if (!state.active) {
      return;
    }
    const label = labelOfItem(state.itemId);
    const itemId = state.itemId;
    reset();
    stopListening();
    announce(message(messages, 'cancelled', label));
    focusItem(itemId);
  }

  function focusItem(itemId) {
    const all = zones();
    const { zone, index } = zoneOfItem(all, itemId);
    const element = zone && zone.items[index] && zone.items[index].element;
    if (element && typeof element.focus === 'function') {
      element.focus();
    }
  }

  function finish() {
    const drop = {
      itemId: state.itemId,
      fromZone: state.fromZone,
      fromIndex: state.fromIndex,
      toZone: state.overZone,
      toIndex: state.overIndex
    };
    const label = labelOfItem(drop.itemId);
    const unchanged =
      !drop.toZone ||
      (drop.toZone === drop.fromZone && drop.toIndex === drop.fromIndex) ||
      !canDrop(drop.itemId, drop.fromZone, drop.toZone);
    const toLabel = zoneLabel(drop.toZone);
    const byKeyboard = state.mode === 'keyboard';
    reset();
    stopListening();
    // A keyboard user keeps focus on the item they moved, once the caller has re-rendered it.
    const refocus = () => {
      if (byKeyboard) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- after the caller's re-render
        setTimeout(() => focusItem(drop.itemId), 0);
      }
    };
    if (unchanged) {
      announce(message(messages, 'cancelled', label));
      refocus();
      return Promise.resolve(false);
    }
    busy = true;
    return Promise.resolve()
      .then(() => onDrop(drop))
      .then((result) => {
        busy = false;
        refocus();
        if (result === false) {
          announce(message(messages, 'cancelled', label));
          return false;
        }
        announce(message(messages, 'dropped', label, toLabel));
        return true;
      })
      .catch(() => {
        busy = false;
        refocus();
        announce(message(messages, 'cancelled', label));
        return false;
      });
  }

  // ---- pointer --------------------------------------------------------------------------

  function onPointerMove(event) {
    if (pending && !state.active) {
      const dx = event.clientX - pending.x;
      const dy = event.clientY - pending.y;
      const moved = Math.sqrt(dx * dx + dy * dy);
      if (pending.touch) {
        if (moved > TOUCH_SLOP) {
          clearPending(); // a scroll, not a drag
        }
        return;
      }
      if (moved < MOUSE_SLOP) {
        return;
      }
      const itemId = pending.itemId;
      pending = null;
      if (!start('pointer', itemId, event.clientX, event.clientY)) {
        stopListening();
        return;
      }
    }
    if (!state.active || state.mode !== 'pointer') {
      return;
    }
    if (event.cancelable) {
      event.preventDefault();
    }
    const all = zones();
    const zone = zoneAt(all, event.clientX, event.clientY);
    const allowed = zone && canDrop(state.itemId, state.fromZone, zone.id);
    setState({
      x: event.clientX,
      y: event.clientY,
      overZone: allowed ? zone.id : null,
      overIndex: allowed ? indexAt(zone, state.itemId, event.clientX, event.clientY) : -1
    });
  }

  function onPointerUp() {
    if (pending && !state.active) {
      clearPending();
      return;
    }
    if (state.active && state.mode === 'pointer') {
      swallowNextClick();
      finish();
    }
  }

  function onPointerCancel() {
    clearPending();
    cancel();
  }

  // While a touch drag is on, the page must not scroll under the finger.
  function onTouchMove(event) {
    if (state.active && state.mode === 'pointer' && event.cancelable) {
      event.preventDefault();
    }
  }

  function onWindowKey(event) {
    if (state.active && state.mode === 'pointer' && event.key === 'Escape') {
      cancel();
    }
  }

  // The click that follows a drop must not open the card under the pointer.
  function swallowNextClick() {
    if (typeof window === 'undefined') {
      return;
    }
    const swallow = (event) => {
      event.stopPropagation();
      event.preventDefault();
      window.removeEventListener('click', swallow, true);
    };
    window.addEventListener('click', swallow, true);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- only the click of this release
    setTimeout(() => window.removeEventListener('click', swallow, true), 0);
  }

  function listen() {
    if (listening || typeof window === 'undefined') {
      return;
    }
    listening = true;
    window.addEventListener('pointermove', onPointerMove, { passive: false });
    window.addEventListener('pointerup', onPointerUp);
    window.addEventListener('pointercancel', onPointerCancel);
    window.addEventListener('touchmove', onTouchMove, { passive: false });
    window.addEventListener('keydown', onWindowKey);
  }

  function stopListening() {
    if (!listening || typeof window === 'undefined') {
      return;
    }
    listening = false;
    window.removeEventListener('pointermove', onPointerMove, { passive: false });
    window.removeEventListener('pointerup', onPointerUp);
    window.removeEventListener('pointercancel', onPointerCancel);
    window.removeEventListener('touchmove', onTouchMove, { passive: false });
    window.removeEventListener('keydown', onWindowKey);
  }

  function clearPending() {
    pending = null;
    if (holdTimer) {
      clearTimeout(holdTimer);
      holdTimer = null;
    }
    if (!state.active) {
      stopListening();
    }
  }

  function pointerDown(event) {
    if (busy || state.active || !event || !event.currentTarget) {
      return;
    }
    if (event.pointerType === 'mouse' && event.button !== 0) {
      return;
    }
    const itemId = event.currentTarget.dataset && event.currentTarget.dataset.dragId;
    if (!itemId) {
      return;
    }
    const touch = event.pointerType === 'touch';
    pending = { itemId, x: event.clientX, y: event.clientY, touch };
    listen();
    if (touch) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation -- the touch press and hold
      holdTimer = setTimeout(() => {
        holdTimer = null;
        if (pending) {
          const { x, y } = pending;
          pending = null;
          if (!start('pointer', itemId, x, y)) {
            stopListening();
          }
        }
      }, holdMs);
    }
  }

  // ---- keyboard -------------------------------------------------------------------------

  function moveKeyboard(zoneStep, indexStep) {
    const all = zones();
    let zoneIndex = all.findIndex((zone) => zone.id === state.overZone);
    let index = state.overIndex;
    if (zoneStep) {
      let next = zoneIndex + zoneStep;
      while (
        next >= 0 &&
        next < all.length &&
        !canDrop(state.itemId, state.fromZone, all[next].id)
      ) {
        next += zoneStep;
      }
      if (next < 0 || next >= all.length) {
        return;
      }
      zoneIndex = next;
      index = Math.min(index, others(all[zoneIndex], state.itemId).length);
    }
    if (indexStep) {
      const max = others(all[zoneIndex], state.itemId).length;
      const next = index + indexStep;
      if (next < 0 || next > max) {
        return;
      }
      index = next;
    }
    setState({ overZone: all[zoneIndex].id, overIndex: index });
    announcePosition();
  }

  function keyDown(event) {
    if (!event || busy) {
      return;
    }
    const key = event.key;
    if (!state.active) {
      // Only the item itself picks up: Space on a button or link inside it keeps its own job.
      if ((key === ' ' || key === 'Spacebar') && event.target === event.currentTarget) {
        const itemId = event.currentTarget && event.currentTarget.dataset.dragId;
        if (itemId && start('keyboard', itemId, 0, 0)) {
          event.preventDefault();
        }
      }
      return;
    }
    if (state.mode !== 'keyboard') {
      return;
    }
    const columns = layout === 'columns';
    const handled = {
      ArrowUp: () => moveKeyboard(0, -1),
      ArrowDown: () => moveKeyboard(0, 1),
      ArrowLeft: () => (columns ? moveKeyboard(-1, 0) : moveKeyboard(0, -1)),
      ArrowRight: () => (columns ? moveKeyboard(1, 0) : moveKeyboard(0, 1)),
      ' ': () => finish(),
      Spacebar: () => finish(),
      Enter: () => finish(),
      Escape: () => cancel(),
      Tab: () => cancel()
    }[key];
    if (handled) {
      if (key !== 'Tab') {
        event.preventDefault();
      }
      event.stopPropagation();
      handled();
    }
  }

  return {
    pointerDown,
    keyDown,
    cancel,
    get state() {
      return state;
    },
    destroy() {
      clearPending();
      stopListening();
      state = IDLE;
    }
  };
}

function isIndex(value, length) {
  return Number.isInteger(value) && value >= 0 && value < length;
}

/**
 * A copy of the list with the item at `from` moved to `to` (onDrop's toIndex, or a Move Up or
 * Move Down target); the list itself is not changed, and a place outside it changes nothing.
 */
export function moveItem(list, from, to) {
  const items = Array.isArray(list) ? list.slice() : [];
  if (!isIndex(from, items.length) || !isIndex(to, items.length) || from === to) {
    return items;
  }
  const [moved] = items.splice(from, 1);
  items.splice(to, 0, moved);
  return items;
}

/** Where Move Up (delta -1) or Move Down (1) takes the item at `index`, or -1 when it cannot. */
export function targetIndex(index, delta, length) {
  const to = index + delta;
  return isIndex(index, length) && isIndex(to, length) ? to : -1;
}

export { format as formatDragMessage };
