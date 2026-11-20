/**
 * Saved Super Transformer step lists (C-50f1, canonical model Section 29P): a named, org-wide
 * definition of an object, a filter and the changes, kept as one version 1 JSON document in
 * `Saved_Transform__c.Definition_JSON__c`.
 *
 *     { "version": 1, "object": "Contact", "filter": { ...Find filter document... },
 *       "changes": [ { "field": "Phone", "action": "transform", "transforms": [ ... ] } ] }
 *
 * A save checks the document's shape and its steps, never the records: loading a list only fills
 * the page in, and a run still compiles the query, checks every field and saves every record as
 * the person who runs it. Every read and write is in user mode, so the object permissions of
 * BarnCRM Bulk Update (read, create, edit, delete) are what grant access; the sharing model is
 * public read and write, so every user of the tool sees every list.
 *
 * A row of Kind Map is a saved map of the Mapper instead (canonical model R-ST5, R-MAP1 to
 * R-MAP3): the step list methods never read or change one, and the map methods never read or
 * change a step list. A row with no Kind reads as a step list.
 */
public with sharing class SavedTransformService {
	public static final String KIND_STEP_LIST = 'StepList';
	public static final String KIND_MAP = 'Map';
	public static final Integer DOCUMENT_VERSION = 1;
	public static final Integer MAX_NAME = 80;
	/** The longest document stored, below the field's 131,072 characters. */
	public static final Integer MAX_DOCUMENT = 100000;
	/** The most lists read for the picker. */
	public static final Integer MAX_LISTS = 200;
	/** The newest map document version (R-MAP1); versions 1 to 3 are import mappings. */
	public static final Integer MAP_VERSION = 4;
	public static final Integer MAX_MAP_COLUMNS = 200;
	public static final Integer MAX_MAP_DEFAULTS = 50;
	/** The longest JSON sample a map keeps for the screen, as JSON text. */
	public static final Integer MAX_MAP_SAMPLE = 20000;

	private static final Set<String> ACTIONS = new Set<String>{
		BulkUpdateService.ACTION_SET,
		BulkUpdateService.ACTION_CLEAR,
		BulkUpdateService.ACTION_COPY,
		BulkUpdateService.ACTION_TRANSFORM
	};
	private static final Set<String> FROM_KINDS = new Set<String>{ 'columns', 'record', 'json' };
	private static final Set<String> TO_KINDS = new Set<String>{ 'record', 'json' };
	private static final Map<String, Set<String>> MATCH_VALUES = new Map<String, Set<String>>{
		'by' => new Set<String>{ 'id', 'field', 'externalId', 'duplicateRules' },
		'several' => new Set<String>{ 'reject', 'newest' },
		'none' => new Set<String>{ 'create', 'skip', 'reject' }
	};
	private static final Set<String> NOT_FOUND = new Set<String>{ 'reject', 'leaveEmpty' };
	/** R-MAP2: up to 10 parts of letters, digits, underscores and hyphens, each with an optional [n]. */
	private static final Pattern PATH_PATTERN = Pattern.compile(
		'^[A-Za-z0-9_-]+(\\[[0-9]{1,3}\\])?(\\.[A-Za-z0-9_-]+(\\[[0-9]{1,3}\\])?){0,9}$'
	);

	/** One list in the picker. */
	public class ListEntry {
		@AuraEnabled
		public String recordId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String objectName;
		/** The object's label, or its API name when the org no longer has it. */
		@AuraEnabled
		public String objectLabel;
	}

	/** One list with its document, for loading. */
	public class SavedList {
		@AuraEnabled
		public String recordId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String objectName;
		@AuraEnabled
		public String definitionJson;
		/**
		 * On load: the filter fields (API names) that are gone or not readable by the person
		 * now. When not empty the page must not load the list (R-ST3).
		 */
		@AuraEnabled
		public List<String> missingFields = new List<String>();
	}

	/** Every saved list, by name. */
	public static List<ListEntry> listAll() {
		return listKind(KIND_STEP_LIST);
	}

	/** Every saved map, by name (R-ST5). */
	public static List<ListEntry> listMaps() {
		return listKind(KIND_MAP);
	}

	private static List<ListEntry> listKind(String kind) {
		List<ListEntry> entries = new List<ListEntry>();
		List<Saved_Transform__c> rows = kind == KIND_MAP
			? [
					SELECT Id, Name, Object_Name__c
					FROM Saved_Transform__c
					WHERE Kind__c = :KIND_MAP
					WITH USER_MODE
					ORDER BY Name
					LIMIT :MAX_LISTS
			  ]
			: [
					SELECT Id, Name, Object_Name__c
					FROM Saved_Transform__c
					WHERE Kind__c != :KIND_MAP
					WITH USER_MODE
					ORDER BY Name
					LIMIT :MAX_LISTS
			  ];
		for (Saved_Transform__c saved : rows) {
			ListEntry entry = new ListEntry();
			entry.recordId = saved.Id;
			entry.name = saved.Name;
			entry.objectName = saved.Object_Name__c;
			entry.objectLabel = objectLabel(saved.Object_Name__c);
			entries.add(entry);
		}
		return entries;
	}

	/**
	 * One list with its document, unchanged. The filter's conditions are checked against the
	 * object's fields as the person sees them now; the API names of fields that are gone or not
	 * readable are returned in `missingFields`. Dropping a condition would match more records,
	 * so the document is never trimmed: the page refuses to load a list with missing fields.
	 */
	public static SavedList load(Id recordId) {
		SavedList view = toView(find(recordId, KIND_STEP_LIST));
		try {
			Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(view.definitionJson);
			Object rawFilter = document.get('filter');
			if (!(rawFilter instanceof Map<String, Object>)) {
				return view;
			}
			Object conditions = ((Map<String, Object>) rawFilter).get('conditions');
			if (!(conditions instanceof List<Object>)) {
				return view;
			}
			for (Object each : (List<Object>) conditions) {
				String field = fieldOf(each);
				if (!fieldUsable(view.objectName, field) && !view.missingFields.contains(field)) {
					view.missingFields.add(field);
				}
			}
		} catch (Exception unreadable) {
			// A document checkDefinition would refuse is returned as stored; the page reports it.
			view.missingFields = new List<String>();
		}
		return view;
	}

	/** One map with its document, unchanged; the Mapper checks its fields as the person (R-MAP3). */
	public static SavedList loadMap(Id recordId) {
		return toView(find(recordId, KIND_MAP));
	}

	/** A condition's field, or a placeholder when it names none. */
	private static String fieldOf(Object condition) {
		Object field = condition instanceof Map<String, Object> ? ((Map<String, Object>) condition).get('field') : null;
		return field instanceof String ? (String) field : '?';
	}

	private static Boolean fieldUsable(String objectName, String field) {
		try {
			QueryFieldCatalog.resolvePath(objectName, field);
			return true;
		} catch (Exception gone) {
			return false;
		}
	}

	/** Saves a new list; the name must be new and the document must pass the checks. */
	public static SavedList save(String name, String definitionJson) {
		String cleaned = cleanName(name, KIND_STEP_LIST);
		String objectName = checkDefinition(definitionJson);
		requireFreeName(cleaned, null, KIND_STEP_LIST);
		Saved_Transform__c saved = new Saved_Transform__c(
			Name = cleaned,
			Object_Name__c = objectName,
			Definition_JSON__c = definitionJson
		);
		insert as user saved;
		return toView(saved);
	}

	/**
	 * Saves a map: a new one when `recordId` is empty, otherwise the map itself, changed in
	 * place, because a tool may link it by its record ID (R-ST5).
	 */
	public static SavedList saveMap(Id recordId, String name, String definitionJson) {
		String cleaned = cleanName(name, KIND_MAP);
		String objectName = checkMap(definitionJson);
		Saved_Transform__c saved = recordId == null
			? new Saved_Transform__c(Kind__c = KIND_MAP)
			: find(recordId, KIND_MAP);
		requireFreeName(cleaned, saved.Id, KIND_MAP);
		saved.Name = cleaned;
		saved.Object_Name__c = objectName;
		saved.Definition_JSON__c = definitionJson;
		upsert as user saved;
		return toView(saved);
	}

	/** Gives a list a new name; its document is untouched. */
	public static SavedList rename(Id recordId, String name) {
		return renameKind(recordId, name, KIND_STEP_LIST);
	}

	/** Gives a map a new name; its document is untouched. */
	public static SavedList renameMap(Id recordId, String name) {
		return renameKind(recordId, name, KIND_MAP);
	}

	private static SavedList renameKind(Id recordId, String name, String kind) {
		Saved_Transform__c saved = find(recordId, kind);
		String cleaned = cleanName(name, kind);
		requireFreeName(cleaned, saved.Id, kind);
		saved.Name = cleaned;
		update as user saved;
		return toView(saved);
	}

	/** Deletes a list. */
	public static void remove(Id recordId) {
		delete as user find(recordId, KIND_STEP_LIST);
	}

	/** Deletes a map. */
	public static void removeMap(Id recordId) {
		delete as user find(recordId, KIND_MAP);
	}

	/**
	 * Checks a document and returns the API name of its object. Refuses a document that is not
	 * version 1 JSON, names an object a bulk update may not write, holds more changes than one
	 * run allows, or has a change whose steps DataTransform names a problem with.
	 */
	public static String checkDefinition(String definitionJson) {
		Map<String, Object> document = readDocument(definitionJson, KIND_STEP_LIST);
		if (document.get('version') != DOCUMENT_VERSION || !(document.get('object') instanceof String)) {
			throw refused(BarnHelp.text('Core', 'Core_SavedTransform_ErrorUnreadable'));
		}
		String objectName = (String) document.get('object');
		requireWritable(objectName);
		if (document.get('filter') != null && !(document.get('filter') instanceof Map<String, Object>)) {
			throw refused(BarnHelp.text('Core', 'Core_SavedTransform_ErrorUnreadable'));
		}
		checkChanges(document.get('changes'));
		return objectName;
	}

	/**
	 * Checks a map document (R-MAP3) and returns its record target's object, or null for a JSON
	 * target or a people map. Field names are not checked here: the Mapper and every tool check
	 * them against describe as the person when the map is loaded, previewed and used.
	 */
	public static String checkMap(String definitionJson) {
		Map<String, Object> document = readDocument(definitionJson, KIND_MAP);
		Object version = document.get('version');
		if (!(version instanceof Integer) || (Integer) version < 1 || (Integer) version > MAP_VERSION) {
			throw refused(BarnHelp.text('Core', 'Core_Map_ErrorUnreadable'));
		}
		Map<String, Object> fromPart = part(document, 'from');
		Map<String, Object> toPart = part(document, 'to');
		String fromKind = kindOf(fromPart, FROM_KINDS, 'columns');
		String toKind = kindOf(toPart, TO_KINDS, 'record');
		if (fromPart.get('sample') != null && JSON.serialize(fromPart.get('sample')).length() > MAX_MAP_SAMPLE) {
			throw refused(BarnHelp.text('Core', 'Core_Map_ErrorTooBig'));
		}
		String objectName = toKind == 'record' ? stringOf(toPart.get('object')) : null;
		if (objectName != null) {
			requireWritable(objectName);
		}
		List<Object> columns = listOf(document.get('columns'));
		List<Object> defaults = listOf(document.get('defaults'));
		if (columns.size() > MAX_MAP_COLUMNS || defaults.size() > MAX_MAP_DEFAULTS) {
			throw refused(
				BarnHelp.text('Core', 'Core_Map_ErrorTooMany', new List<Object>{ MAX_MAP_COLUMNS, MAX_MAP_DEFAULTS })
			);
		}
		Set<String> targets = new Set<String>();
		for (Integer i = 0; i < columns.size(); i++) {
			checkMapColumn(columns[i], i + 1, fromKind == 'json', toKind == 'json', targets);
		}
		for (Object each : defaults) {
			if (
				!(each instanceof Map<String, Object>) || stringOf(((Map<String, Object>) each).get('target')) == null
			) {
				throw refused(BarnHelp.text('Core', 'Core_Map_ErrorUnreadable'));
			}
		}
		checkMatch(document.get('match'));
		return objectName;
	}

	private static void checkMapColumn(
		Object entry,
		Integer line,
		Boolean jsonSource,
		Boolean jsonTarget,
		Set<String> targets
	) {
		Map<String, Object> column = entry instanceof Map<String, Object> ? (Map<String, Object>) entry : null;
		String target = column == null ? null : stringOf(column.get('target'));
		String source = column == null ? null : stringOf(column.get('source'));
		Object value = column == null ? null : column.get('value');
		Boolean broken =
			target == null ||
			(jsonTarget && !isPath(target)) ||
			(source == null && !(value instanceof String)) ||
			(value instanceof String && ((String) value).length() > DataTransform.MAX_TEXT) ||
			(source != null &&
			jsonSource &&
			!isPath(source)) ||
			(column.get('required') != null && !(column.get('required') instanceof Boolean)) ||
			!lookupUsable(column.get('lookup'));
		if (broken) {
			throw refused(BarnHelp.text('Core', 'Core_Map_ErrorColumn', new List<Object>{ line }));
		}
		if (!targets.add(target.toLowerCase())) {
			throw refused(BarnHelp.text('Core', 'Core_Map_ErrorTargetTwice', new List<Object>{ target }));
		}
		checkSteps(target, column.get('transforms'));
	}

	private static Boolean lookupUsable(Object raw) {
		if (raw == null) {
			return true;
		}
		Map<String, Object> lookup = raw instanceof Map<String, Object> ? (Map<String, Object>) raw : null;
		return lookup != null &&
			stringOf(lookup.get('object')) != null &&
			stringOf(lookup.get('field')) != null &&
			(lookup.get('notFound') == null || NOT_FOUND.contains(stringOf(lookup.get('notFound'))));
	}

	private static void checkMatch(Object raw) {
		if (raw == null) {
			return;
		}
		Map<String, Object> match = raw instanceof Map<String, Object> ? (Map<String, Object>) raw : null;
		Boolean usable = match != null && MATCH_VALUES.get('by').contains(stringOf(match.get('by')));
		for (String key : new List<String>{ 'several', 'none' }) {
			usable = usable && (match.get(key) == null || MATCH_VALUES.get(key).contains(stringOf(match.get(key))));
		}
		String way = usable ? stringOf(match.get('by')) : null;
		if (!usable || ((way == 'field' || way == 'externalId') && stringOf(match.get('field')) == null)) {
			throw refused(BarnHelp.text('Core', 'Core_Map_ErrorMatch'));
		}
	}

	/** True for an R-MAP2 path. */
	public static Boolean isPath(String path) {
		return path != null && PATH_PATTERN.matcher(path).matches();
	}

	private static Map<String, Object> readDocument(String definitionJson, String kind) {
		Boolean isMap = kind == KIND_MAP;
		if (String.isBlank(definitionJson) || definitionJson.length() > MAX_DOCUMENT) {
			throw refused(
				isMap
					? BarnHelp.text('Core', 'Core_Map_ErrorTooBig')
					: BarnHelp.text('Core', 'Core_SavedTransform_ErrorTooBig')
			);
		}
		try {
			return (Map<String, Object>) JSON.deserializeUntyped(definitionJson);
		} catch (Exception unreadable) {
			throw refused(
				isMap
					? BarnHelp.text('Core', 'Core_Map_ErrorUnreadable')
					: BarnHelp.text('Core', 'Core_SavedTransform_ErrorUnreadable')
			);
		}
	}

	private static void requireWritable(String objectName) {
		if (!BulkUpdateFields.isWritable(objectName)) {
			throw refused(
				String.format(BarnHelp.text('Core', 'Core_SavedTransform_ErrorObject'), new List<Object>{ objectName })
			);
		}
	}

	/** A part of the map (`from`, `to`); absent reads as empty, anything else is refused. */
	private static Map<String, Object> part(Map<String, Object> document, String key) {
		Object raw = document.get(key);
		if (raw != null && !(raw instanceof Map<String, Object>)) {
			throw refused(BarnHelp.text('Core', 'Core_Map_ErrorUnreadable'));
		}
		return raw == null ? new Map<String, Object>() : (Map<String, Object>) raw;
	}

	private static String kindOf(Map<String, Object> part, Set<String> allowed, String fallback) {
		String kind = part.get('kind') == null ? fallback : stringOf(part.get('kind'));
		if (!allowed.contains(kind)) {
			throw refused(BarnHelp.text('Core', 'Core_Map_ErrorUnreadable'));
		}
		return kind;
	}

	private static List<Object> listOf(Object raw) {
		if (raw != null && !(raw instanceof List<Object>)) {
			throw refused(BarnHelp.text('Core', 'Core_Map_ErrorUnreadable'));
		}
		return raw == null ? new List<Object>() : (List<Object>) raw;
	}

	/** Non-blank text, or null. */
	private static String stringOf(Object raw) {
		return raw instanceof String && String.isNotBlank((String) raw) ? (String) raw : null;
	}

	private static void checkChanges(Object rawChanges) {
		if (!(rawChanges instanceof List<Object>)) {
			throw refused(BarnHelp.text('Core', 'Core_SavedTransform_ErrorUnreadable'));
		}
		List<Object> changes = (List<Object>) rawChanges;
		if (changes.size() > BulkUpdateService.MAX_CHANGES) {
			throw refused(
				String.format(
					BarnHelp.text('Core', 'Core_SavedTransform_ErrorChanges'),
					new List<Object>{ BulkUpdateService.MAX_CHANGES }
				)
			);
		}
		for (Object each : changes) {
			Map<String, Object> change = each instanceof Map<String, Object> ? (Map<String, Object>) each : null;
			if (
				change == null ||
				!(change.get('field') instanceof String) ||
				!(change.get('action') instanceof String) ||
				!ACTIONS.contains((String) change.get('action'))
			) {
				throw refused(
					String.format(
						BarnHelp.text('Core', 'Core_SavedTransform_ErrorChanges'),
						new List<Object>{ BulkUpdateService.MAX_CHANGES }
					)
				);
			}
			if (change.get('action') == BulkUpdateService.ACTION_TRANSFORM) {
				checkSteps((String) change.get('field'), change.get('transforms'));
			}
		}
	}

	private static void checkSteps(String field, Object rawSteps) {
		List<DataTransform.Step> steps = rawSteps instanceof List<Object>
			? DataTransform.parse(JSON.serialize(rawSteps))
			: new List<DataTransform.Step>();
		List<String> problems = DataTransform.problems(steps);
		if (!problems.isEmpty()) {
			throw refused(
				String.format(
					BarnHelp.text('Core', 'Core_SavedTransform_ErrorSteps'),
					new List<Object>{ field, String.join(problems, ' ') }
				)
			);
		}
	}

	private static String cleanName(String name, String kind) {
		String cleaned = name == null ? '' : name.normalizeSpace();
		if (cleaned.length() == 0 || cleaned.length() > MAX_NAME) {
			throw refused(
				kind == KIND_MAP
					? BarnHelp.text('Core', 'Core_Map_ErrorName', new List<Object>{ MAX_NAME })
					: String.format(
							BarnHelp.text('Core', 'Core_SavedTransform_ErrorName'),
							new List<Object>{ MAX_NAME }
					  )
			);
		}
		return cleaned;
	}

	/** A list may not share a name (capitals ignored) with another of its kind. */
	private static void requireFreeName(String name, Id except, String kind) {
		List<Saved_Transform__c> same = kind == KIND_MAP
			? [
					SELECT Id
					FROM Saved_Transform__c
					WHERE Name = :name AND Id != :except AND Kind__c = :KIND_MAP
					WITH USER_MODE
					LIMIT 1
			  ]
			: [
					SELECT Id
					FROM Saved_Transform__c
					WHERE Name = :name AND Id != :except AND Kind__c != :KIND_MAP
					WITH USER_MODE
					LIMIT 1
			  ];
		if (!same.isEmpty()) {
			throw refused(
				kind == KIND_MAP
					? BarnHelp.text('Core', 'Core_Map_ErrorExists', new List<Object>{ name })
					: String.format(BarnHelp.text('Core', 'Core_SavedTransform_ErrorExists'), new List<Object>{ name })
			);
		}
	}

	/** The row of this kind, or a refusal: a step list is never found as a map, nor a map as a list. */
	private static Saved_Transform__c find(Id recordId, String kind) {
		List<Saved_Transform__c> found = recordId == null
			? new List<Saved_Transform__c>()
			: [
					SELECT Id, Name, Object_Name__c, Definition_JSON__c, Kind__c
					FROM Saved_Transform__c
					WHERE Id = :recordId
					WITH USER_MODE
					LIMIT 1
			  ];
		if (found.isEmpty() || (found[0].Kind__c == KIND_MAP) != (kind == KIND_MAP)) {
			throw refused(
				kind == KIND_MAP
					? BarnHelp.text('Core', 'Core_Map_ErrorNotFound')
					: BarnHelp.text('Core', 'Core_SavedTransform_ErrorNotFound')
			);
		}
		return found[0];
	}

	private static SavedList toView(Saved_Transform__c saved) {
		SavedList view = new SavedList();
		view.recordId = saved.Id;
		view.name = saved.Name;
		view.objectName = saved.Object_Name__c;
		view.definitionJson = saved.Definition_JSON__c;
		return view;
	}

	private static String objectLabel(String objectName) {
		try {
			return QueryFieldCatalog.describeObject(objectName).getLabel();
		} catch (Exception gone) {
			return objectName;
		}
	}

	private static BulkUpdateFields.BulkUpdateException refused(String message) {
		return new BulkUpdateFields.BulkUpdateException(message);
	}
}
