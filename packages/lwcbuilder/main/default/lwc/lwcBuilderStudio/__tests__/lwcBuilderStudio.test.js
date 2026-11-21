import { createElement } from 'lwc';
import LwcBuilderStudio from 'c/lwcBuilderStudio';
import getStudio from '@salesforce/apex/LwcBuilderController.getStudio';
import saveComponent from '@salesforce/apex/LwcBuilderController.saveComponent';
import { setHelpTextForTest } from 'c/barnHelpText';
import { createDragController } from 'c/barnDrag';

jest.mock('c/barnDrag', () => ({
  createDragController: jest.fn(() => ({
    pointerDown: jest.fn(),
    keyDown: jest.fn(),
    cancel: jest.fn(),
    destroy: jest.fn()
  }))
}));

/** The options the studio gave the drag controller, so a test can drop as the controller would. */
function dragOptions() {
  const calls = createDragController.mock.calls;
  return calls[calls.length - 1][0];
}

const HELP = require('../../../staticresources/BarnHelp_LwcBuilder.json').texts;

setHelpTextForTest({
  LwcBuilder_Studio_Title: HELP.LwcBuilder_Studio_Title,
  LwcBuilder_Studio_Choose: HELP.LwcBuilder_Studio_Choose
});

jest.mock('@salesforce/apex/LwcBuilderController.getStudio', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/LwcBuilderController.saveComponent', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/LwcBuilderController.loadComponent', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/LwcBuilderController.checkPermissions',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/LwcBuilderController.loadRecords', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/LwcBuilderController.loadChart', () => ({ default: jest.fn() }), {
  virtual: true
});

const SAVED = {
  id: 'a0B000000000001AAA',
  name: 'Saved One',
  key: 'Saved_One',
  objectName: 'Contact',
  active: true,
  version: 3,
  definition: JSON.stringify({
    schemaVersion: 1,
    sections: [
      {
        id: 's1',
        title: 'Saved',
        rows: [{ id: 'r1', columns: [{ id: 'c1', width: 12, blocks: [] }] }]
      }
    ]
  })
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount() {
  const element = createElement('c-lwc-builder-studio', { is: LwcBuilderStudio });
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

function type(input, value) {
  input.value = value;
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

function palette(element, blockType) {
  return [...findAll(element, 'palette')].find((button) => button.dataset.type === blockType);
}

describe('c-lwc-builder-studio', () => {
  beforeEach(() => {
    getStudio.mockResolvedValue({ components: [SAVED], sourceExport: true, canEdit: true });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('starts a section from a block and fills the key from the name', async () => {
    const element = await mount();
    expect(find(element, 'empty-canvas')).not.toBeNull();

    palette(element, 'text').click();
    await flush();
    expect(findAll(element, 'section')).toHaveLength(1);
    expect(findAll(element, 'block')).toHaveLength(1);
    expect(find(element, 'prop-title')).not.toBeNull();

    type(find(element, 'name'), 'Donor Snapshot');
    await flush();
    expect(find(element, 'key').value).toBe('Donor_Snapshot');
  });

  it('selects a column from the keyboard', async () => {
    const element = await mount();
    find(element, 'add-section').click();
    await flush();
    const column = find(element, 'column');
    expect(column.getAttribute('tabindex')).toBe('0');
    expect(column.getAttribute('role')).toBe('button');

    const space = new KeyboardEvent('keydown', { key: ' ', bubbles: true, cancelable: true });
    column.dispatchEvent(space);
    await flush();

    expect(space.defaultPrevented).toBe(true);
    expect(find(element, 'column').getAttribute('aria-pressed')).toBe('true');
  });

  it('uses pointer and key drag from c/barnDrag, never HTML5 drag and drop', async () => {
    const element = await mount();
    find(element, 'add-section').click();
    await flush();
    palette(element, 'image').click();
    await flush();

    const item = palette(element, 'image').parentElement;
    expect(item.hasAttribute('draggable')).toBe(false);
    expect(item.dataset.dragId).toBe('palette:image');
    expect(find(element, 'palette-zone').dataset.dropZone).toBe('palette');
    const column = find(element, 'column');
    expect(column.dataset.dropZone).toBeTruthy();
    expect(find(element, 'block').hasAttribute('draggable')).toBe(false);
    expect(find(element, 'block').dataset.dragId).toBeTruthy();
    // Nothing can be dropped back on the block list.
    expect(dragOptions().canDrop('b1', column.dataset.dropZone, 'palette')).toBe(false);
  });

  it('drops a block from the list onto a column, before the block it lands on', async () => {
    const element = await mount();
    find(element, 'add-section').click();
    await flush();
    palette(element, 'text').click();
    await flush();
    const columnId = find(element, 'column').dataset.dropZone;
    const first = find(element, 'block').dataset.dragId;

    await dragOptions().onDrop({
      itemId: 'palette:image',
      fromZone: 'palette',
      toZone: columnId,
      toIndex: 0
    });
    await flush();

    const blocks = findAll(element, 'block');
    expect(blocks).toHaveLength(2);
    expect(blocks[1].dataset.dragId).toBe(first);
  });

  it('moves a block within its column and refuses a drop with no column', async () => {
    const element = await mount();
    find(element, 'add-section').click();
    await flush();
    palette(element, 'text').click();
    await flush();
    palette(element, 'image').click();
    await flush();
    const columnId = find(element, 'column').dataset.dropZone;
    const [a, b] = [...findAll(element, 'block')].map((block) => block.dataset.dragId);

    expect(await dragOptions().onDrop({ itemId: b, toZone: null, toIndex: -1 })).toBe(false);
    await dragOptions().onDrop({ itemId: b, fromZone: columnId, toZone: columnId, toIndex: 0 });
    await flush();

    expect([...findAll(element, 'block')].map((block) => block.dataset.dragId)).toEqual([b, a]);
  });

  it('lists what is missing instead of saving', async () => {
    const element = await mount();
    palette(element, 'fields').click();
    await flush();
    find(element, 'save').click();
    await flush();
    expect(saveComponent).not.toHaveBeenCalled();
    expect(findAll(element, 'problem').length).toBeGreaterThan(0);
  });

  it('saves the details and the definition as one JSON document', async () => {
    saveComponent.mockResolvedValue({ ...SAVED, id: 'a0B000000000002AAA', version: 1 });
    const element = await mount();
    palette(element, 'text').click();
    await flush();
    type(find(element, 'name'), 'Donor Snapshot');
    await flush();
    find(element, 'save').click();
    await flush();

    const sent = JSON.parse(saveComponent.mock.calls[0][0].componentJson);
    expect(sent).toEqual(
      expect.objectContaining({ name: 'Donor Snapshot', key: 'Donor_Snapshot', active: true })
    );
    expect(sent.definition.sections[0].rows[0].columns[0].blocks[0].type).toBe('text');
    expect(getStudio).toHaveBeenCalledTimes(2);
  });

  it('titles the page Component Builder and asks to choose a component', async () => {
    const element = await mount();
    expect(find(element, 'card').title).toBe('Component Builder');
    expect(find(element, 'pick').placeholder).toBe('Choose a Component');
  });

  it('opens a saved component and exports it as three files', async () => {
    const element = await mount();
    const pick = find(element, 'pick');
    pick.dispatchEvent(new CustomEvent('change', { detail: { value: SAVED.id } }));
    await flush();
    expect(find(element, 'key').value).toBe('Saved_One');
    expect(findAll(element, 'section')).toHaveLength(1);

    find(element, 'export').click();
    await flush();
    expect(findAll(element, 'export-file')).toHaveLength(3);
  });

  it('previews the definition being built', async () => {
    const element = await mount();
    palette(element, 'text').click();
    await flush();
    find(element, 'preview').click();
    await flush();
    const preview = find(element, 'preview-view');
    expect(preview.definition.sections).toHaveLength(1);
  });
});
