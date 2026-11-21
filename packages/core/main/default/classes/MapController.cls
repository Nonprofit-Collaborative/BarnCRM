/**
 * The Mapper (integration hub design Section 2; canonical model R-MAP1 to R-MAP4 and R-ST5):
 * saved maps, the fields a record map can fill, and the server half of the preview. The screen's
 * logic lives in the framework-free module `mapDocument`; this class only reads describe, runs
 * the R-IT15 steps and looks lookups up, all as the person, and saves nothing but maps.
 *
 * Listing and loading a map need only read access to Saved Transform (every tool that uses a map
 * reads it in user mode); saving, renaming, deleting, the field list and the preview need Manage
 * BarnCRM Settings.
 */
public with sharing class MapController {
	/** The most samples one preview or Check Before Running reads (R-MAP4). */
	public static final Integer MAX_SAMPLES = 200;
	/** The most parent records one lookup reads in a preview. */
	private static final Integer MAX_LOOKUP_ROWS = 2000;
	/** The most object and field pairs one preview looks parents up by, one query each. */
	@TestVisible
	private static final Integer MAX_LOOKUP_FIELDS = 50;
	/** A refusal is shown as written and not logged; anything else is logged. */
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
		null,
		null,
		System.Label.Core_UnexpectedError
	);

	/** What a map produces from each sample. */
	public class Preview {
		@AuraEnabled
		public List<PreviewSample> samples = new List<PreviewSample>();
	}

	public class PreviewSample {
		@AuraEnabled
		public List<PreviewValue> values = new List<PreviewValue>();
	}

	/** One target's value; for a lookup column, whether the parent was found. */
	public class PreviewValue {
		@AuraEnabled
		public String target;
		@AuraEnabled
		public String value;
		/** found, none or several; empty when the column has no lookup or the value is blank. */
		@AuraEnabled
		public String lookup;
	}

	@AuraEnabled
	public static List<SavedTransformService.ListEntry> listMaps() {
		try {
			return SavedTransformService.listMaps();
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'MapController.listMaps');
		}
	}

	@AuraEnabled
	public static SavedTransformService.SavedList loadMap(Id recordId) {
		try {
			return SavedTransformService.loadMap(recordId);
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'MapController.loadMap');
		}
	}

	/** Saves a new map (no record ID) or changes one in place. */
	@AuraEnabled
	public static SavedTransformService.SavedList saveMap(Id recordId, String name, String definitionJson) {
		try {
			requireManage();
			return SavedTransformService.saveMap(recordId, name, definitionJson);
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'MapController.saveMap');
		}
	}

	@AuraEnabled
	public static SavedTransformService.SavedList renameMap(Id recordId, String name) {
		try {
			requireManage();
			return SavedTransformService.renameMap(recordId, name);
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'MapController.renameMap');
		}
	}

	@AuraEnabled
	public static void deleteMap(Id recordId) {
		try {
			requireManage();
			SavedTransformService.removeMap(recordId);
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'MapController.deleteMap');
		}
	}

	/** The tools that link this map, from the installed modules (Where Used, C-59). */
	@AuraEnabled
	public static List<WhereUsedService.Reference> mapUsers(Id recordId) {
		try {
			requireManage();
			SavedTransformService.SavedList saved = SavedTransformService.loadMap(recordId);
			return WhereUsedService.mapUsers(saved.recordId, saved.name);
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'MapController.mapUsers');
		}
	}

	/** The objects a record map may fill: those a bulk update may write. */
	@AuraEnabled(cacheable=true)
	public static List<FindController.Option> getObjects() {
		try {
			requireManage();
			List<FindController.Option> writable = new List<FindController.Option>();
			for (FindController.Option option : FindController.listObjects()) {
				if (BulkUpdateFields.isWritable(option.value)) {
					writable.add(option);
				}
			}
			return writable;
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'MapController.getObjects');
		}
	}

	/** The fields of a record map's object the person may write, with what the checks need. */
	@AuraEnabled(cacheable=true)
	public static List<BulkUpdateFields.Target> getTargetFields(String objectName) {
		try {
			requireManage();
			return BulkUpdateFields.targets(objectName);
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'MapController.getTargetFields');
		}
	}

	/**
	 * Runs a map over samples and returns each target's value (R-MAP4). `samplesJson` is a list of
	 * objects, each a source name and its raw value, as the screen read them from a file row, a
	 * record or a JSON payload. Each column's steps run with the sample's other values (an
	 * `append` step reads them); a blank result takes the target's default; a lookup is looked up
	 * as the person. Nothing is saved.
	 */
	@AuraEnabled
	public static Preview previewMap(String definitionJson, String samplesJson) {
		try {
			requireManage();
			SavedTransformService.checkMap(definitionJson);
			Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(definitionJson);
			List<Map<String, String>> samples = samplesOf(samplesJson);
			Map<String, String> defaults = new Map<String, String>();
			for (Object each : listOf(document.get('defaults'))) {
				Map<String, Object> entry = (Map<String, Object>) each;
				defaults.put(String.valueOf(entry.get('target')), textOf(entry.get('value')));
			}
			Preview preview = new Preview();
			for (Integer i = 0; i < samples.size(); i++) {
				preview.samples.add(new PreviewSample());
			}
			// Lookup columns that find by the same object and field share one query.
			List<Object> columns = listOf(document.get('columns'));
			List<List<String>> valuesOf = new List<List<String>>();
			List<String> lookupKeys = new List<String>();
			Map<String, List<String>> lookupValues = new Map<String, List<String>>();
			Map<String, Map<String, Object>> lookups = new Map<String, Map<String, Object>>();
			for (Object each : columns) {
				Map<String, Object> column = (Map<String, Object>) each;
				List<String> values = columnValues(column, samples, defaults.remove((String) column.get('target')));
				valuesOf.add(values);
				String key;
				if (column.get('lookup') instanceof Map<String, Object>) {
					Map<String, Object> lookup = (Map<String, Object>) column.get('lookup');
					key = (lookup.get('object') + '.' + lookup.get('field')).toLowerCase();
					if (!lookups.containsKey(key)) {
						lookups.put(key, lookup);
						lookupValues.put(key, new List<String>());
					}
					lookupValues.get(key).addAll(values);
				}
				lookupKeys.add(key);
			}
			if (lookups.size() > MAX_LOOKUP_FIELDS) {
				throw new BulkUpdateFields.BulkUpdateException(
					BarnHelp.text('Core', 'Core_Map_ErrorTooManyLookups', new List<Object>{ MAX_LOOKUP_FIELDS })
				);
			}
			Map<String, Map<String, String>> foundBy = new Map<String, Map<String, String>>();
			for (String key : lookups.keySet()) {
				foundBy.put(key, lookUp(lookups.get(key), lookupValues.get(key)));
			}
			for (Integer c = 0; c < columns.size(); c++) {
				String target = (String) ((Map<String, Object>) columns[c]).get('target');
				Map<String, String> found = lookupKeys[c] == null ? null : foundBy.get(lookupKeys[c]);
				for (Integer i = 0; i < samples.size(); i++) {
					preview.samples[i].values.add(valueOf(target, valuesOf[c][i], found));
				}
			}
			// A default for a target no column fills is the value of every sample.
			for (String target : defaults.keySet()) {
				for (PreviewSample sample : preview.samples) {
					sample.values.add(valueOf(target, defaults.get(target), null));
				}
			}
			return preview;
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'MapController.previewMap');
		}
	}

	private static List<String> columnValues(
		Map<String, Object> column,
		List<Map<String, String>> samples,
		String fallback
	) {
		List<DataTransform.Step> steps = column.get('transforms') instanceof List<Object>
			? DataTransform.parse(JSON.serialize(column.get('transforms')))
			: new List<DataTransform.Step>();
		Object fixed = column.get('value');
		String sourceKey = ImportMapping.key((String) column.get('source'));
		List<String> values = new List<String>();
		for (Map<String, String> sample : samples) {
			String raw = fixed instanceof String ? (String) fixed : sample.get(sourceKey);
			String value = DataTransform.apply(steps, raw, sample);
			values.add(String.isBlank(value) && fallback != null ? fallback : value);
		}
		return values;
	}

	private static PreviewValue valueOf(String target, String value, Map<String, String> found) {
		PreviewValue entry = new PreviewValue();
		entry.target = target;
		entry.value = value;
		if (found != null && String.isNotBlank(value)) {
			String status = found.get(value.trim().toLowerCase());
			entry.lookup = status == null ? 'none' : status;
		}
		return entry;
	}

	/**
	 * For each distinct value, whether the lookup's object has one record (`found`), several or
	 * none whose field equals it, read in user mode. The object and field are checked against
	 * describe as the person; a field path or a field that cannot be filtered is refused.
	 */
	private static Map<String, String> lookUp(Map<String, Object> lookup, List<String> values) {
		String objectName = (String) lookup.get('object');
		String fieldName = (String) lookup.get('field');
		Schema.DescribeSObjectResult described = QueryFieldCatalog.describeObject(objectName);
		Schema.DescribeFieldResult field = fieldName.contains('.')
			? null
			: QueryFieldCatalog.resolvePath(objectName, fieldName);
		if (field == null || !field.isFilterable()) {
			throw new BulkUpdateFields.BulkUpdateException(
				BarnHelp.text('Core', 'Core_Map_ErrorLookup', new List<Object>{ fieldName, objectName })
			);
		}
		Boolean byId = field.getType() == Schema.DisplayType.ID;
		Set<String> wanted = new Set<String>();
		for (String value : values) {
			String key = String.isBlank(value) ? null : value.trim();
			if (key != null && byId) {
				key = key instanceof Id ? String.valueOf(Id.valueOf(key)) : null;
			}
			if (key != null) {
				wanted.add(key);
			}
		}
		Map<String, Integer> counts = new Map<String, Integer>();
		if (!wanted.isEmpty()) {
			String name = field.getName();
			for (
				SObject row : Database.queryWithBinds(
					'SELECT ' + name + ' FROM ' + described.getName() + ' WHERE ' + name + ' IN :wanted LIMIT :most',
					new Map<String, Object>{ 'wanted' => wanted, 'most' => MAX_LOOKUP_ROWS },
					AccessLevel.USER_MODE
				)
			) {
				String key = String.valueOf(row.get(name)).toLowerCase();
				counts.put(key, counts.containsKey(key) ? counts.get(key) + 1 : 1);
			}
		}
		Map<String, String> found = new Map<String, String>();
		for (String value : values) {
			if (String.isBlank(value)) {
				continue;
			}
			String key = value.trim();
			if (byId) {
				key = key instanceof Id ? String.valueOf(Id.valueOf(key)) : '';
			}
			Integer count = counts.get(key.toLowerCase());
			found.put(value.trim().toLowerCase(), count == null ? 'none' : (count == 1 ? 'found' : 'several'));
		}
		return found;
	}

	/** The samples as name to raw value, keyed as DataTransform reads another value. */
	private static List<Map<String, String>> samplesOf(String samplesJson) {
		List<Map<String, String>> samples = new List<Map<String, String>>();
		Object raw = String.isBlank(samplesJson) ? null : JSON.deserializeUntyped(samplesJson);
		for (Object each : raw instanceof List<Object> ? (List<Object>) raw : new List<Object>()) {
			if (samples.size() >= MAX_SAMPLES) {
				break;
			}
			Map<String, String> sample = new Map<String, String>();
			if (each instanceof Map<String, Object>) {
				Map<String, Object> values = (Map<String, Object>) each;
				for (String name : values.keySet()) {
					sample.put(ImportMapping.key(name), textOf(values.get(name)));
				}
			}
			samples.add(sample);
		}
		return samples;
	}

	private static String textOf(Object value) {
		return value == null ? null : String.valueOf(value);
	}

	private static List<Object> listOf(Object raw) {
		return raw instanceof List<Object> ? (List<Object>) raw : new List<Object>();
	}

	private static void requireManage() {
		if (!BarnCRMPermissions.canManageSettings()) {
			throw new BulkUpdateFields.BulkUpdateException(BarnHelp.text('Core', 'Core_Map_ErrorNoPermission'));
		}
	}
}
