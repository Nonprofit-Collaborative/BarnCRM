import { LightningElement, api } from 'lwc';
import { helpText } from 'c/barnHelpText';
import { MODES, isPill, syncSlots } from 'c/connectorRecipeRules';

/**
 * The fields of a recipe whose When is An App Has New Items (CN-13; canonical model R-CR16;
 * design Section 3.2): the connection, the list's path and its values, query parameters, where
 * the list, each item's id and its stamp sit in the app's answer, and how runs start. Hands each
 * change to the editor as `triggerchange`; the editor's rules check the whole trigger.
 */
export default class ConnectorAppPollSetup extends LightningElement {
  @api trigger = {};
  @api connections = [];
  @api readOnly = false;

  labels = {
    get connection() {
      return helpText('Connector', 'Connector_Editor_Connection');
    },
    get path() {
      return helpText('Connector', 'Connector_Editor_Path');
    },
    get pathHelp() {
      return helpText('Connector', 'Connector_Poll_PathHelp');
    },
    get valueHelp() {
      return helpText('Connector', 'Connector_Poll_ValueHelp');
    },
    get queryParams() {
      return helpText('Connector', 'Connector_Editor_QueryParams');
    },
    get entryName() {
      return helpText('Connector', 'Connector_Editor_EntryName');
    },
    get entryValue() {
      return helpText('Connector', 'Connector_Editor_EntryValue');
    },
    get addEntry() {
      return helpText('Connector', 'Connector_Editor_AddEntry');
    },
    get remove() {
      return helpText('Connector', 'Connector_Editor_Remove');
    },
    get items() {
      return helpText('Connector', 'Connector_Poll_Items');
    },
    get itemsHelp() {
      return helpText('Connector', 'Connector_Poll_ItemsHelp');
    },
    get itemId() {
      return helpText('Connector', 'Connector_Poll_ItemId');
    },
    get itemIdHelp() {
      return helpText('Connector', 'Connector_Poll_ItemIdHelp');
    },
    get stamp() {
      return helpText('Connector', 'Connector_Poll_Stamp');
    },
    get stampHelp() {
      return helpText('Connector', 'Connector_Poll_StampHelp');
    },
    get mode() {
      return helpText('Connector', 'Connector_Editor_Mode');
    },
    get limit() {
      return helpText('Connector', 'Connector_Poll_Limit');
    },
    get limitHelp() {
      return helpText('Connector', 'Connector_Poll_LimitHelp');
    }
  };

  get starter() {
    return this.trigger || {};
  }

  get modeOptions() {
    return MODES.map((value) => ({
      label:
        value === 'batch'
          ? helpText('Connector', 'Connector_Poll_Mode_batch')
          : helpText('Connector', 'Connector_Poll_Mode_each'),
      value
    }));
  }

  get canEdit() {
    return !this.readOnly;
  }

  /** Each `{name}` of the path with the value that fills it. */
  get pathValues() {
    return (this.starter.pathValues || []).map((entry, index) => ({
      key: `slot-${entry.name}`,
      index,
      name: entry.name,
      shown: entry.path || entry.value || ''
    }));
  }

  get query() {
    return (this.starter.query || []).map((entry, index) => ({
      key: `query-${index}`,
      index,
      name: entry.name || '',
      shown: entry.path || entry.value || ''
    }));
  }

  change(changes) {
    this.dispatchEvent(new CustomEvent('triggerchange', { detail: changes }));
  }

  /** A plain field: data-field names it; the limit is a number, blank for the default. */
  handleField(event) {
    const field = event.target.dataset.field;
    let value = event.detail.value;
    if (field === 'limit') {
      value = value === '' || value === null || value === undefined ? undefined : Number(value);
    }
    const changes = { [field]: value };
    if (field === 'path') {
      changes.pathValues = syncSlots(value, this.starter.pathValues);
    }
    this.change(changes);
  }

  /** One path value or query parameter: `trigger.watermark` is kept as a path, anything else as text. */
  handleEntry(event) {
    const { list, index, field } = event.target.dataset;
    const entries = [...(this.starter[list] || [])];
    const entry = { ...entries[Number(index)] };
    if (field === 'shown') {
      const typed = event.detail.value;
      delete entry.path;
      delete entry.value;
      if (isPill(typed)) {
        entry.path = typed;
      } else {
        entry.value = typed;
      }
    } else {
      entry[field] = event.detail.value;
    }
    entries[Number(index)] = entry;
    this.change({ [list]: entries });
  }

  handleAddQuery() {
    this.change({ query: [...(this.starter.query || []), { name: '', value: '' }] });
  }

  handleRemoveQuery(event) {
    const entries = [...(this.starter.query || [])];
    entries.splice(Number(event.target.dataset.index), 1);
    this.change({ query: entries });
  }
}
