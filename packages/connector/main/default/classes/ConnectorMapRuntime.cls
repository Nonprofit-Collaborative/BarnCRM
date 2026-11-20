/**
 * The Mapper's runtime for records and JSON bodies (design Section 2.1: the runtime lives in the
 * Connector, not Core; canonical model R-MAP1 to R-MAP3). Applies a saved map document to one
 * input (a run's trigger data, a found record, an app's answer): reads each column's source by
 * path, runs its R-IR15 steps through Core's `DataTransform`, falls back to the defaults, finds
 * lookups, and builds either a record of the map's object, typed by describe, or a JSON body.
 * Nothing in a path or a value is evaluated (ADR-0081).
 *
 * Every read and write runs in the access mode the caller gives: user mode for BarnCRM Automation
 * and the Flow action, system mode only for a System recipe (R-CR4). Inherited sharing: a System
 * recipe's steps are called through `ConnectorRunStore.runInSystemMode`, so sharing is skipped
 * there and nowhere else.
 */
public inherited sharing class ConnectorMapRuntime {
	public static final String KIND_MAP = 'Map';
	private static final Pattern SEGMENT = Pattern.compile('([A-Za-z0-9_-]+)(?:\\[([0-9]{1,3})\\])?');

	/** A map refused or a value that does not fit: the message is for a person. */
	public class MapException extends Exception {
	}

	/** A saved map as a run uses it. */
	public class SavedMap {
		public Id recordId;
		public String name;
		public Map<String, Object> document;
		/** The map's last change, kept on the run as the version it used. */
		public Datetime version;
	}

	/** What a record map built: the record and the values found for its match. */
	public class Built {
		public SObject record;
		public Schema.DescribeSObjectResult described;
		/** Field API names set, in map order. */
		public List<String> fields = new List<String>();
	}

	/** A saved map by Id (R-ST5: read in the run's access mode); refused when gone. */
	public static SavedMap load(String mapId, AccessLevel access) {
		List<Saved_Transform__c> rows = ConnectorRecipeDocument.isId(mapId)
			? Database.queryWithBinds(
					'SELECT Id, Name, Definition_JSON__c, LastModifiedDate FROM Saved_Transform__c ' +
					'WHERE Id = :mapId AND Kind__c = :kind LIMIT 1',
					new Map<String, Object>{ 'mapId' => mapId, 'kind' => KIND_MAP },
					access
			  )
			: new List<Saved_Transform__c>();
		if (rows.isEmpty()) {
			throw new MapException(BarnHelp.text('Connector', 'Connector_Run_ErrorMapGone'));
		}
		SavedMap found = new SavedMap();
		found.recordId = rows[0].Id;
		found.name = rows[0].Name;
		found.version = rows[0].LastModifiedDate;
		Object raw;
		try {
			raw = JSON.deserializeUntyped(rows[0].Definition_JSON__c);
		} catch (Exception unreadable) {
			raw = null;
		}
		found.document = ConnectorRecipeDocument.mapOf(raw);
		return found;
	}

	/** The target object of a record map, or blank for a JSON map. */
	public static String objectOf(Map<String, Object> document) {
		Map<String, Object> target = ConnectorRecipeDocument.mapOf(document.get('to'));
		return ConnectorRecipeDocument.textOf(target.get('kind')) == 'json'
			? ''
			: ConnectorRecipeDocument.textOf(target.get('object'));
	}

	// ---------------------------------------------------------------------------------------
	// Paths (R-MAP2): read, never evaluated
	// ---------------------------------------------------------------------------------------

	/** The value a path finds in data, or null. A key with no path syntax is read as it is. */
	public static Object read(Object data, String path) {
		if (String.isBlank(path)) {
			return data;
		}
		if (data instanceof Map<String, Object> && ((Map<String, Object>) data).containsKey(path)) {
			return ((Map<String, Object>) data).get(path);
		}
		Object current = data;
		for (String part : path.split('\\.')) {
			Matcher matched = SEGMENT.matcher(part);
			if (!matched.matches() || !(current instanceof Map<String, Object>)) {
				return null;
			}
			current = ((Map<String, Object>) current).get(matched.group(1));
			if (matched.group(2) != null) {
				Integer index = Integer.valueOf(matched.group(2));
				List<Object> items = current instanceof List<Object> ? (List<Object>) current : null;
				current = items != null && index < items.size() ? items[index] : null;
			}
		}
		return current;
	}

	/** A value as text: blank stays null, a list or object becomes its JSON. */
	public static String text(Object value) {
		if (value == null) {
			return null;
		}
		if (value instanceof Map<String, Object> || value instanceof List<Object>) {
			return JSON.serialize(value);
		}
		return String.valueOf(value);
	}

	// ---------------------------------------------------------------------------------------
	// Columns to values
	// ---------------------------------------------------------------------------------------

	/**
	 * Each target and its value for one input: a fixed value, or the source read by path, then
	 * the column's steps; a blank result takes the target's default. A column whose value is
	 * read untouched keeps the input's own type (a number stays a number in a JSON body).
	 */
	@TestVisible
	private static Map<String, Object> values(Map<String, Object> document, Object input) {
		Map<String, Object> defaults = new Map<String, Object>();
		for (Object raw : ConnectorRecipeDocument.listOf(document.get('defaults'))) {
			Map<String, Object> entry = ConnectorRecipeDocument.mapOf(raw);
			defaults.put(ConnectorRecipeDocument.textOf(entry.get('target')), entry.get('value'));
		}
		List<Map<String, Object>> columns = new List<Map<String, Object>>();
		Map<String, String> others = new Map<String, String>();
		for (Object raw : ConnectorRecipeDocument.listOf(document.get('columns'))) {
			Map<String, Object> column = ConnectorRecipeDocument.mapOf(raw);
			columns.add(column);
			String source = ConnectorRecipeDocument.textOf(column.get('source'));
			if (String.isNotBlank(source)) {
				others.put(DataTransform.key(source), text(read(input, source)));
			}
		}
		Map<String, Object> result = new Map<String, Object>();
		for (Map<String, Object> column : columns) {
			String target = ConnectorRecipeDocument.textOf(column.get('target'));
			Object raw = column.get('value') instanceof String
				? column.get('value')
				: read(input, ConnectorRecipeDocument.textOf(column.get('source')));
			Object value = raw;
			if (column.get('transforms') instanceof List<Object>) {
				List<DataTransform.Step> steps = DataTransform.parse(JSON.serialize(column.get('transforms')));
				value = DataTransform.apply(steps, text(raw), others);
			}
			if (String.isBlank(text(value)) && defaults.containsKey(target)) {
				value = defaults.get(target);
			}
			if (column.get('required') == true && String.isBlank(text(value))) {
				throw new MapException(
					BarnHelp.text('Connector', 'Connector_Run_ErrorRequired', new List<Object>{ target })
				);
			}
			result.put(target, value);
			defaults.remove(target);
		}
		for (String target : defaults.keySet()) {
			result.put(target, defaults.get(target));
		}
		return result;
	}

	// ---------------------------------------------------------------------------------------
	// JSON bodies
	// ---------------------------------------------------------------------------------------

	/** The JSON body a map with `to.kind` json builds from one input. */
	public static Map<String, Object> buildJson(Map<String, Object> document, Object input) {
		Map<String, Object> body = new Map<String, Object>();
		Map<String, Object> found = values(document, input);
		for (String target : found.keySet()) {
			put(body, target, found.get(target));
		}
		return body;
	}

	/** Puts a value at a path, making the objects and lists on the way. */
	private static void put(Map<String, Object> body, String path, Object value) {
		Object current = body;
		List<String> parts = path.split('\\.');
		for (Integer i = 0; i < parts.size(); i++) {
			Matcher matched = SEGMENT.matcher(parts[i]);
			if (!matched.matches()) {
				return;
			}
			Boolean last = i == parts.size() - 1;
			Map<String, Object> holder = (Map<String, Object>) current;
			String key = matched.group(1);
			if (matched.group(2) == null) {
				if (last) {
					holder.put(key, value);
					return;
				}
				if (!(holder.get(key) instanceof Map<String, Object>)) {
					holder.put(key, new Map<String, Object>());
				}
				current = holder.get(key);
				continue;
			}
			if (!(holder.get(key) instanceof List<Object>)) {
				holder.put(key, new List<Object>());
			}
			List<Object> items = (List<Object>) holder.get(key);
			Integer index = Integer.valueOf(matched.group(2));
			while (items.size() <= index) {
				items.add(last ? null : new Map<String, Object>());
			}
			if (last) {
				items[index] = value;
				return;
			}
			if (!(items[index] instanceof Map<String, Object>)) {
				items[index] = new Map<String, Object>();
			}
			current = items[index];
		}
	}

	// ---------------------------------------------------------------------------------------
	// Records
	// ---------------------------------------------------------------------------------------

	/**
	 * The record a map with `to.kind` record builds from one input, each value typed for its
	 * field. A field that is gone, that the identity cannot write (user mode) or a value that does
	 * not fit is refused with the field's name; lookups are found in the given access mode.
	 */
	public static Built buildRecord(Map<String, Object> document, Object input, AccessLevel access, Boolean creating) {
		String objectName = objectOf(document);
		List<Schema.DescribeSObjectResult> described = String.isBlank(objectName)
			? new List<Schema.DescribeSObjectResult>()
			: Schema.describeSObjects(new List<String>{ objectName });
		if (described.isEmpty()) {
			throw new MapException(BarnHelp.text('Connector', 'Connector_Run_ErrorMapObject'));
		}
		Built built = new Built();
		built.described = described[0];
		built.record = built.described.getSObjectType().newSObject();
		Map<String, Schema.SObjectField> fields = built.described.fields.getMap();
		Map<String, Map<String, Object>> lookups = new Map<String, Map<String, Object>>();
		for (Object raw : ConnectorRecipeDocument.listOf(document.get('columns'))) {
			Map<String, Object> column = ConnectorRecipeDocument.mapOf(raw);
			if (column.get('lookup') instanceof Map<String, Object>) {
				lookups.put(
					ConnectorRecipeDocument.textOf(column.get('target')),
					(Map<String, Object>) column.get('lookup')
				);
			}
		}
		Map<String, Object> found = values(document, input);
		for (String target : found.keySet()) {
			String fieldName = target.removeStart('Record.');
			Schema.SObjectField token = fields.get(fieldName.toLowerCase());
			if (token == null) {
				throw new MapException(
					BarnHelp.text('Connector', 'Connector_Run_ErrorField', new List<Object>{ fieldName })
				);
			}
			Schema.DescribeFieldResult field = token.getDescribe();
			Boolean writable = creating ? field.isCreateable() : field.isUpdateable();
			if (field.getName() != 'Id' && access == AccessLevel.USER_MODE && !writable) {
				throw new MapException(
					BarnHelp.text('Connector', 'Connector_Run_ErrorFieldAccess', new List<Object>{ field.getLabel() })
				);
			}
			String value = text(found.get(target));
			if (lookups.containsKey(target) && String.isNotBlank(value)) {
				value = lookUp(lookups.get(target), value.trim(), access, field.getLabel());
			}
			built.record.put(field.getName(), typed(field, value));
			built.fields.add(field.getName());
		}
		return built;
	}

	/** The Id of the one record whose field equals the value, or blank when leaveEmpty allows it. */
	private static String lookUp(Map<String, Object> lookup, String value, AccessLevel access, String label) {
		String objectName = ConnectorRecipeDocument.textOf(lookup.get('object'));
		String fieldName = ConnectorRecipeDocument.textOf(lookup.get('field'));
		List<Schema.DescribeSObjectResult> described = Pattern.matches('[A-Za-z0-9_]{1,80}', objectName)
			? Schema.describeSObjects(new List<String>{ objectName })
			: new List<Schema.DescribeSObjectResult>();
		Schema.SObjectField token = described.isEmpty()
			? null
			: described[0].fields.getMap().get(fieldName.toLowerCase());
		if (token == null || !token.getDescribe().isFilterable()) {
			throw new MapException(BarnHelp.text('Connector', 'Connector_Run_ErrorLookup', new List<Object>{ label }));
		}
		List<SObject> rows = Database.queryWithBinds(
			'SELECT Id FROM ' +
				described[0].getName() +
				' WHERE ' +
				token.getDescribe().getName() +
				' = :value LIMIT 2',
			new Map<String, Object>{ 'value' => value },
			access
		);
		if (rows.size() == 1) {
			return rows[0].Id;
		}
		if (rows.isEmpty() && ConnectorRecipeDocument.textOf(lookup.get('notFound')) == 'leaveEmpty') {
			return null;
		}
		List<Object> named = new List<Object>{ label, value };
		throw new MapException(
			rows.isEmpty()
				? BarnHelp.text('Connector', 'Connector_Run_ErrorLookupNone', named)
				: BarnHelp.text('Connector', 'Connector_Run_ErrorLookupSeveral', named)
		);
	}

	/** Text as the field's type; a value that does not fit is refused with the field's label. */
	@TestVisible
	private static Object typed(Schema.DescribeFieldResult field, String value) {
		if (String.isBlank(value)) {
			return field.getType() == Schema.DisplayType.BOOLEAN ? (Object) false : null;
		}
		String trimmed = value.trim();
		try {
			switch on field.getType() {
				when BOOLEAN {
					return new Set<String>{ 'true', '1', 'yes', 'y' }.contains(trimmed.toLowerCase());
				}
				when DATE {
					return Date.valueOf(trimmed.left(10));
				}
				when DATETIME {
					return (Datetime) JSON.deserialize('"' + trimmed.replace('"', '') + '"', Datetime.class);
				}
				when INTEGER {
					return Integer.valueOf(trimmed);
				}
				when DOUBLE, CURRENCY, PERCENT {
					return Decimal.valueOf(trimmed);
				}
				when REFERENCE, ID {
					return Id.valueOf(trimmed);
				}
				when else {
					Integer most = field.getLength();
					if (most > 0 && trimmed.length() > most) {
						throw new MapException();
					}
					return value;
				}
			}
		} catch (Exception unfit) {
			throw new MapException(
				BarnHelp.text('Connector', 'Connector_Run_ErrorValue', new List<Object>{ field.getLabel() })
			);
		}
	}

	// ---------------------------------------------------------------------------------------
	// Saving (create, update, create or update)
	// ---------------------------------------------------------------------------------------

	/** What a save did: the record's Id and created, updated or skipped. */
	public class Saved {
		public Id recordId;
		public String action;
		public Map<String, Object> fields = new Map<String, Object>();
	}

	/**
	 * Saves a built record (R-CR1): `create` inserts; `update` writes the record with the Id
	 * given; `upsert` finds the existing record by the map's `match` (R-IT2 semantics: by Id, by a
	 * field or external Id; several reject or the newest; none creates, skips or rejects). With
	 * `dryRun` nothing is saved and the fields it would write are returned (R-CR5).
	 */
	public static Saved save(
		String kind,
		Map<String, Object> document,
		Object input,
		Id recordId,
		Id ownerId,
		AccessLevel access,
		Boolean dryRun
	) {
		Built built = buildRecord(document, input, access, kind != 'update');
		Saved result = new Saved();
		for (String field : built.fields) {
			result.fields.put(field, built.record.get(field));
		}
		Id existing = kind == 'update' ? recordId : null;
		if (kind == 'upsert') {
			existing = matched(ConnectorRecipeDocument.mapOf(document.get('match')), built, access);
			if (
				existing == null &&
				ConnectorRecipeDocument.textOf(ConnectorRecipeDocument.mapOf(document.get('match')).get('none')) ==
				'skip'
			) {
				result.action = 'skipped';
				return result;
			}
		}
		if (kind == 'update' && (existing == null || existing.getSObjectType() != built.described.getSObjectType())) {
			throw new MapException(BarnHelp.text('Connector', 'Connector_Run_ErrorRecordId'));
		}
		result.action = existing == null ? 'created' : 'updated';
		if (existing == null && ownerId != null && built.described.fields.getMap().containsKey('ownerid')) {
			built.record.put('OwnerId', ownerId);
		}
		if (dryRun) {
			result.recordId = existing;
			return result;
		}
		if (existing == null) {
			built.record.put('Id', null);
			// Access mode: the caller's AccessLevel (user mode unless the recipe runs as System).
			Database.insert(built.record, access);
		} else {
			built.record.put('Id', existing);
			// Access mode: the caller's AccessLevel (user mode unless the recipe runs as System).
			Database.update(built.record, access);
		}
		result.recordId = built.record.Id;
		return result;
	}

	/** The existing record a Create or Update finds through the map's match, or null. */
	private static Id matched(Map<String, Object> match, Built built, AccessLevel access) {
		String matchBy = ConnectorRecipeDocument.textOf(match.get('by'));
		if (matchBy == 'id') {
			Object value = built.record.get('Id');
			return value == null ? null : (Id) value;
		}
		if (matchBy != 'field' && matchBy != 'externalId') {
			throw new MapException(BarnHelp.text('Connector', 'Connector_Run_ErrorMatch'));
		}
		String fieldName = ConnectorRecipeDocument.textOf(match.get('field'));
		Schema.SObjectField token = built.described.fields.getMap().get(fieldName.toLowerCase());
		Object value = token == null ? null : built.record.get(token);
		if (token == null || value == null || !token.getDescribe().isFilterable()) {
			throw new MapException(BarnHelp.text('Connector', 'Connector_Run_ErrorMatch'));
		}
		List<SObject> rows = Database.queryWithBinds(
			'SELECT Id FROM ' +
				built.described.getName() +
				' WHERE ' +
				token.getDescribe().getName() +
				' = :value ORDER BY CreatedDate DESC LIMIT 2',
			new Map<String, Object>{ 'value' => value },
			access
		);
		if (rows.size() > 1 && ConnectorRecipeDocument.textOf(match.get('several')) != 'newest') {
			throw new MapException(BarnHelp.text('Connector', 'Connector_Run_ErrorMatchSeveral'));
		}
		if (rows.isEmpty() && ConnectorRecipeDocument.textOf(match.get('none')) == 'reject') {
			throw new MapException(BarnHelp.text('Connector', 'Connector_Run_ErrorMatchNone'));
		}
		return rows.isEmpty() ? null : rows[0].Id;
	}
}
