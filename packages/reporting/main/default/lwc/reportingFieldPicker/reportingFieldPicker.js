import { LightningElement, api } from 'lwc';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import { helpText } from 'c/barnHelpText';
import { format } from 'c/barnFormat';
import { messageFrom } from 'c/findCsv';
import { DATE_TYPES, NUMBER_TYPES, namePath } from 'c/reportingModel';

/** How many lookups a path may cross (QueryFieldCatalog.MAX_PARENT_DEPTH). */
const MAX_DEPTH = 2;
const HOP = '>';

/** Which fields each use offers. */
const KINDS = {
  column: () => true,
  group: (field) => field.groupable || field.dataType === 'datetime',
  sum: (field) => field.aggregatable && NUMBER_TYPES.has(field.dataType),
  minmax: (field) =>
    field.aggregatable && (NUMBER_TYPES.has(field.dataType) || DATE_TYPES.has(field.dataType)),
  distinct: (field) => field.groupable,
  date: (field) => field.filterable && DATE_TYPES.has(field.dataType),
  reference: (field) => field.filterable && field.dataType === 'reference' && !!field.referenceTo,
  sortable: (field) => field.sortable
};

const objectCache = new Map();

function loadObject(objectApiName) {
  if (!objectCache.has(objectApiName)) {
    objectCache.set(
      objectApiName,
      getObjectInfo({ objectApiName }).catch((error) => {
        objectCache.delete(objectApiName);
        throw error;
      })
    );
  }
  return objectCache.get(objectApiName);
}

/**
 * Picks one field of an object for Advanced Reporting, crossing up to two lookups (Gift, then
 * Fund, then a Fund field). One list per step; a lookup shows twice, as itself and as "Fund >"
 * to reach its record's fields. Only the fields the person can read are offered
 * (QueryFieldCatalog). Fires `change` with `{ path, label, type, picklist, referenceTo,
 * labelPath }`, where `labelPath` is the record name path of a lookup, for groupings.
 */
export default class ReportingFieldPicker extends LightningElement {
  /** The field list's label. */
  @api label = '';

  /** Which fields to offer: column, group, sum, minmax, distinct, date, reference or sortable. */
  @api kind = 'column';

  /** Whether lookups may be crossed; off for a related-records field, which must be direct. */
  @api direct = false;

  @api required = false;
  @api disabled = false;

  levels = [];
  error = '';
  _object = '';
  _value = '';

  @api
  get objectApiName() {
    return this._object;
  }
  set objectApiName(value) {
    const changed = value !== this._object;
    this._object = value || '';
    if (changed && this.isConnected) {
      this.build();
    }
  }

  /** The chosen field path, such as `Gift__r.Fund__c`. */
  @api
  get value() {
    return this._value;
  }
  set value(next) {
    const changed = (next || '') !== this._value;
    this._value = next || '';
    if (changed && this.isConnected) {
      this.build();
    }
  }

  connectedCallback() {
    this.build();
  }

  /** Lays out the steps for the current object and value. */
  async build() {
    this.error = '';
    if (!this._object) {
      this.levels = [];
      return;
    }
    try {
      const parts = this._value ? this._value.split('.') : [];
      const levels = [];
      let objectName = this._object;
      let prefix = '';
      let labelPrefix = '';
      for (let depth = 0; depth <= MAX_DEPTH; depth++) {
        // eslint-disable-next-line no-await-in-loop
        const info = await loadObject(objectName);
        const level = {
          key: `l${depth}`,
          depth,
          object: objectName,
          prefix,
          labelPrefix,
          info,
          selected: ''
        };
        levels.push(level);
        const part = parts[depth];
        if (part === undefined) {
          break;
        }
        if (depth < parts.length - 1) {
          const hop = info.fields.find(
            (field) => field.relationshipName === part && field.referenceTo
          );
          if (!hop) {
            break;
          }
          level.selected = HOP + hop.apiName;
          objectName = hop.referenceTo;
          prefix = `${prefix}${hop.relationshipName}.`;
          labelPrefix = `${labelPrefix}${stripId(hop.label)}: `;
        } else {
          level.selected = part;
          break;
        }
      }
      this.levels = levels;
    } catch (error) {
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    }
  }

  get steps() {
    const test = KINDS[this.kind] || KINDS.column;
    const hopWord = helpText('Reporting', 'Reporting_FieldHop');
    return this.levels.map((level, index) => {
      const options = [];
      for (const field of level.info.fields) {
        if (test(field)) {
          options.push({ label: field.label, value: field.apiName });
        }
        if (
          !this.direct &&
          field.referenceTo &&
          field.relationshipName &&
          level.depth < MAX_DEPTH
        ) {
          options.push({
            label: format(hopWord, stripId(field.label)),
            value: HOP + field.apiName
          });
        }
      }
      options.sort((left, right) => left.label.localeCompare(right.label));
      return {
        key: level.key,
        index,
        label:
          index === 0
            ? this.label
            : format(helpText('Reporting', 'Reporting_FieldOf'), level.info.label),
        options,
        value: level.selected
      };
    });
  }

  handlePick(event) {
    const index = Number(event.target.dataset.index);
    const picked = event.detail.value;
    const level = this.levels[index];
    if (picked.startsWith(HOP)) {
      const field = level.info.fields.find((entry) => entry.apiName === picked.slice(HOP.length));
      const nextLevels = this.levels.slice(0, index + 1);
      nextLevels[index] = { ...level, selected: picked };
      loadObject(field.referenceTo)
        .then((info) => {
          nextLevels.push({
            key: `l${index + 1}`,
            depth: index + 1,
            object: field.referenceTo,
            prefix: `${level.prefix}${field.relationshipName}.`,
            labelPrefix: `${level.labelPrefix}${stripId(field.label)}: `,
            info,
            selected: ''
          });
          this.levels = nextLevels;
        })
        .catch((error) => {
          this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
        });
      return;
    }
    const field = level.info.fields.find((entry) => entry.apiName === picked);
    const path = `${level.prefix}${field.apiName}`;
    this._value = path;
    const levels = this.levels.slice(0, index + 1);
    levels[index] = { ...level, selected: picked };
    this.levels = levels;
    this.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          path,
          label: `${level.labelPrefix}${field.label}`,
          type: field.dataType,
          referenceTo: field.referenceTo || '',
          labelPath:
            field.dataType === 'reference' && field.referenceTo
              ? namePath(path, field.relationshipName)
              : null,
          picklist: (field.picklistValues || []).reduce(
            (map, option) => ({ ...map, [option.value]: option.label }),
            {}
          )
        }
      })
    );
  }

  /** Clears the choice (the X beside an optional field). */
  @api
  clear() {
    this._value = '';
    this.build();
  }
}

/** "Fund ID" reads as "Fund" when it leads to the fund's fields. */
function stripId(label) {
  return String(label).replace(/\s+ID$/, '');
}
