/**
 * Extra fields the Opportunity mirror copies through a saved map (MAP-07, canonical model
 * R-OM12): the map chosen in `Opportunity_Mirror_Map__c`, from Gift to Opportunity, read once per
 * transaction in system mode, as the setting naming it is. It adds, never replaces: a column for
 * a field R-OM3 writes, a lookup, a gift field the saver cannot read and an Opportunity field the
 * saver cannot create and edit are left out. Used by `OpportunityMirrorContext`.
 */
public with sharing class OpportunityMirrorMap {
	private static final String KIND_MAP = 'Map';
	private static final String RECORD_PREFIX = 'record.';
	/** The Opportunity fields R-OM3 writes itself. */
	private static final Set<String> KEPT = new Set<String>{
		'amount',
		'closedate',
		'stagename',
		'accountid',
		'campaignid',
		'name',
		'recordtypeid'
	};

	private static OpportunityMirrorMap loaded;

	/** One extra field: where its value comes from, its steps and its When Blank, Use value. */
	private class Copy {
		Schema.DescribeFieldResult source;
		String value;
		Schema.DescribeFieldResult target;
		List<DataTransform.Step> steps;
		String fallback;
	}

	private final List<Copy> copies = new List<Copy>();

	/** The map for this transaction: empty when none is named or it cannot be used. */
	public static OpportunityMirrorMap current() {
		if (loaded == null) {
			loaded = new OpportunityMirrorMap(ModuleSettings.text('Mirror_Opportunity_Mirror_Map'));
		}
		return loaded;
	}

	@TestVisible
	private static void forget() {
		loaded = null;
	}

	/**
	 * Whether the setting's value is this map: its record ID, or, for a value stored as a name,
	 * its name.
	 */
	public static Boolean links(String value, Id mapId, String mapName) {
		Id chosen = idOf(value);
		return String.isNotBlank(value) && (chosen != null ? chosen == mapId : value.equalsIgnoreCase(mapName));
	}

	/** The value as a Saved Transform record ID, or null when it is a name. */
	private static Id idOf(String value) {
		try {
			Id candidate = value instanceof Id ? Id.valueOf(value) : null;
			return candidate != null && candidate.getSObjectType() == Saved_Transform__c.SObjectType ? candidate : null;
		} catch (Exception notAnId) {
			return null;
		}
	}

	/** `value` is the map's record ID; a name is read too, so a value stored as a name works. */
	@TestVisible
	private OpportunityMirrorMap(String value) {
		Schema.SObjectType opportunity = OpportunityMirrorContext.opportunityType();
		if (String.isBlank(value) || opportunity == null) {
			return;
		}
		Id mapId = idOf(value);
		List<Saved_Transform__c> rows = mapId != null
			? [
					SELECT Definition_JSON__c
					FROM Saved_Transform__c
					WHERE Id = :mapId AND Kind__c = :KIND_MAP
					WITH SYSTEM_MODE
					LIMIT 1
			  ]
			: [
					SELECT Definition_JSON__c
					FROM Saved_Transform__c
					WHERE Name = :value AND Kind__c = :KIND_MAP
					WITH SYSTEM_MODE
					LIMIT 1
			  ];
		Map<String, Object> document = rows.isEmpty() ? null : asMap(parsed(rows[0].Definition_JSON__c));
		if (
			document == null ||
			!names(document.get('from'), Gift__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)) ||
			!names(document.get('to'), opportunity.getDescribe())
		) {
			return;
		}
		Map<String, String> fallbacks = new Map<String, String>();
		for (Object each : asList(document.get('defaults'))) {
			Map<String, Object> entry = asMap(each);
			if (entry != null && entry.get('target') instanceof String && entry.get('value') instanceof String) {
				fallbacks.put(((String) entry.get('target')).toLowerCase(), (String) entry.get('value'));
			}
		}
		Map<String, Schema.SObjectField> giftFields = Gift__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
			.fields.getMap();
		Map<String, Schema.SObjectField> opportunityFields = opportunity.getDescribe().fields.getMap();
		for (Object each : asList(document.get('columns'))) {
			Copy copy = copyOf(asMap(each), giftFields, opportunityFields);
			if (copy != null) {
				copy.fallback = fallbacks.get(RECORD_PREFIX + copy.target.getName().toLowerCase());
				copies.add(copy);
			}
		}
	}

	/** The gift fields the map reads, for the runs' query and for R-OM4. */
	public List<String> sourceFields() {
		Set<String> names = new Set<String>();
		for (Copy copy : copies) {
			if (copy.source != null) {
				names.add(copy.source.getName());
			}
		}
		return new List<String>(names);
	}

	/**
	 * The gift fields the map reads that `listed` (API names joined by `, `, the package's own
	 * fields) lacks, compared by local name too, so a namespaced org never selects one twice.
	 */
	public List<String> sourceFieldsBesides(String listed) {
		Set<String> taken = new Set<String>(listed.toLowerCase().split(', '));
		List<String> names = new List<String>();
		for (Copy copy : copies) {
			if (
				copy.source != null &&
				!taken.contains(copy.source.getLocalName().toLowerCase()) &&
				taken.add(copy.source.getName().toLowerCase())
			) {
				names.add(copy.source.getName());
			}
		}
		return names;
	}

	/** The Opportunity fields it writes, for the read of linked Opportunities and the comparison. */
	public List<String> targetFields() {
		List<String> names = new List<String>();
		for (Copy copy : copies) {
			names.add(copy.target.getName());
		}
		return names;
	}

	/** Puts each extra field's value for this gift; a value the field cannot take is left out. */
	public void apply(Gift__c gift, SObject opportunity) {
		for (Copy copy : copies) {
			String start = copy.source == null
				? copy.value
				: BulkUpdateFields.toText(copy.source, gift.get(copy.source.getName()));
			String result = DataTransform.apply(copy.steps, start, null);
			if (String.isBlank(result) && copy.fallback != null) {
				result = copy.fallback;
			}
			try {
				opportunity.put(copy.target.getName(), BulkUpdateFields.fromText(copy.target, result));
			} catch (BulkUpdateFields.BulkUpdateException cannotTake) {
				// R-OM12: that field is left out for this gift; the rest of the copy goes ahead.
				continue;
			}
		}
	}

	private static Copy copyOf(
		Map<String, Object> column,
		Map<String, Schema.SObjectField> giftFields,
		Map<String, Schema.SObjectField> opportunityFields
	) {
		String target = column == null || !(column.get('target') instanceof String)
			? ''
			: ((String) column.get('target')).toLowerCase();
		Schema.SObjectField targetField = target.startsWith(RECORD_PREFIX)
			? opportunityFields.get(target.substring(RECORD_PREFIX.length()))
			: null;
		if (targetField == null || column.get('lookup') != null || column.get('lookupField') != null) {
			return null;
		}
		Copy copy = new Copy();
		copy.target = targetField.getDescribe();
		if (
			KEPT.contains(target.substring(RECORD_PREFIX.length())) ||
			!copy.target.isCreateable() ||
			!copy.target.isUpdateable()
		) {
			return null;
		}
		Object source = column.get('source');
		if (source instanceof String && String.isNotBlank((String) source)) {
			Schema.SObjectField sourceField = giftFields.get(((String) source).toLowerCase());
			if (sourceField == null || !sourceField.getDescribe().isAccessible()) {
				return null;
			}
			copy.source = sourceField.getDescribe();
		} else if (column.get('value') instanceof String) {
			copy.value = (String) column.get('value');
		} else {
			return null;
		}
		Object steps = column.get('transforms');
		copy.steps = steps instanceof List<Object>
			? DataTransform.parse(JSON.serialize(steps))
			: new List<DataTransform.Step>();
		return DataTransform.problems(copy.steps).isEmpty() ? copy : null;
	}

	/** Whether a map's `from` or `to` is the record of this object (with or without a namespace). */
	private static Boolean names(Object part, Schema.DescribeSObjectResult described) {
		Map<String, Object> side = asMap(part);
		Object objectName = side == null || !'record'.equals(side.get('kind')) ? null : side.get('object');
		return objectName instanceof String &&
			(described.getName().equalsIgnoreCase((String) objectName) ||
			described.getLocalName().equalsIgnoreCase((String) objectName));
	}

	private static Object parsed(String definition) {
		try {
			return JSON.deserializeUntyped(definition);
		} catch (JSONException unreadable) {
			return null;
		}
	}

	private static Map<String, Object> asMap(Object value) {
		return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
	}

	private static List<Object> asList(Object value) {
		return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
	}
}
