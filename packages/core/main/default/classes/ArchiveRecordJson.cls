/**
 * The Archived Record JSON (canonical model R-ARC2, ADR-NEXT archive rules and big object archive):
 * a record and its cascade-delete children written as one row, the people it names, and the
 * records a restore builds from it. Describe and JSON only: no query, no DML.
 */
public with sharing class ArchiveRecordJson {
	/** The most characters `Record_JSON__c` holds. */
	public static final Integer MAX_JSON = 131072;
	/** The most characters `Person_Ids__c` holds. */
	public static final Integer MAX_PEOPLE = 32768;
	private static final Integer VERSION = 1;

	/** One kind of child the platform deletes with a record: its object and its lookup field. */
	public class ChildKind {
		public String objectName;
		public String fieldName;

		public ChildKind(String objectName, String fieldName) {
			this.objectName = objectName;
			this.fieldName = fieldName;
		}
	}

	/** What a restore builds from one row: the record, its children, and what it left out. */
	public class Restored {
		public SObject record;
		public Map<String, List<SObject>> childrenByObject = new Map<String, List<SObject>>();
		public Map<String, String> parentFieldByObject = new Map<String, String>();
		public List<String> dropped = new List<String>();
	}

	/**
	 * The cascade-delete children of an object the running person may read, as the bulk delete
	 * preview lists them (less sharing, history, feed and change event rows).
	 */
	public static List<ChildKind> childKinds(Schema.DescribeSObjectResult described) {
		List<ChildKind> result = new List<ChildKind>();
		Set<String> seen = new Set<String>();
		for (Schema.ChildRelationship child : described.getChildRelationships()) {
			if (!child.isCascadeDelete() || child.getChildSObject() == null || child.getField() == null) {
				continue;
			}
			Schema.DescribeSObjectResult childObject = child.getChildSObject()
				.getDescribe(SObjectDescribeOptions.DEFERRED);
			String name = childObject.getName();
			if (
				!childObject.isAccessible() ||
				!childObject.isQueryable() ||
				BulkDeleteService.isSystemChild(name) ||
				seen.contains(name)
			) {
				continue;
			}
			seen.add(name);
			result.add(new ChildKind(name, child.getField().getDescribe().getName()));
		}
		return result;
	}

	/** The JSON of a record and its children, by child object. */
	public static String toJson(SObject record, Map<String, List<SObject>> childrenByObject, Map<String, String> fieldByObject) {
		Map<String, Object> children = new Map<String, Object>();
		for (String objectName : childrenByObject.keySet()) {
			List<SObject> rows = childrenByObject.get(objectName);
			if (rows == null || rows.isEmpty()) {
				continue;
			}
			children.put(
				objectName,
				new Map<String, Object>{ 'field' => fieldByObject.get(objectName), 'rows' => rows }
			);
		}
		return JSON.serialize(
			new Map<String, Object>{ 'version' => VERSION, 'record' => record, 'children' => children }
		);
	}

	/**
	 * Contact and Account Ids the record and its children name in their lookups, and the record's
	 * own Id when it is one, comma separated: what erasure looks for (R-ARC6).
	 */
	public static String peopleOf(SObject record, List<SObject> children) {
		Set<String> people = new Set<String>();
		List<SObject> all = new List<SObject>{ record };
		all.addAll(children);
		for (SObject one : all) {
			for (Object value : one.getPopulatedFieldsAsMap().values()) {
				if (value instanceof Id) {
					Schema.SObjectType type = ((Id) value).getSObjectType();
					if (type == Contact.SObjectType || type == Account.SObjectType) {
						people.add(String.valueOf(value));
					}
				}
			}
		}
		return people.isEmpty() ? null : String.join(new List<String>(people), ',').left(MAX_PEOPLE);
	}

	/** Whether the people list names this person. */
	public static Boolean names(String people, String personId) {
		return String.isNotBlank(people) && String.isNotBlank(personId) && people.split(',').contains(personId);
	}

	/** The record a row holds, as it was read. */
	public static SObject recordOf(String body) {
		Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
		return (SObject) JSON.deserialize(JSON.serialize(parsed.get('record')), SObject.class);
	}

	/** Each child object's rows as they were read, by child object. */
	public static Map<String, List<SObject>> childrenOf(String body, Map<String, String> fieldByObject) {
		Map<String, List<SObject>> result = new Map<String, List<SObject>>();
		Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
		Map<String, Object> children = (Map<String, Object>) parsed.get('children');
		if (children == null) {
			return result;
		}
		for (String objectName : children.keySet()) {
			Map<String, Object> kind = (Map<String, Object>) children.get(objectName);
			fieldByObject.put(objectName, (String) kind.get('field'));
			result.put(
				objectName,
				(List<SObject>) JSON.deserialize(JSON.serialize(kind.get('rows')), List<SObject>.class)
			);
		}
		return result;
	}

	/**
	 * The new record and children a restore inserts: only fields the running person may create,
	 * and a lookup only when `existing` holds its target. The children's parent lookup is left
	 * for the caller to fill once the parent has its new Id.
	 */
	public static Restored restore(String body, Set<Id> existing) {
		Restored result = new Restored();
		SObject original = recordOf(body);
		result.record = copy(original, null, existing, result.dropped, '');
		Map<String, List<SObject>> children = childrenOf(body, result.parentFieldByObject);
		for (String objectName : children.keySet()) {
			List<SObject> rows = new List<SObject>();
			String parentField = result.parentFieldByObject.get(objectName);
			for (SObject child : children.get(objectName)) {
				SObject made = copy(child, parentField, existing, result.dropped, objectName + '.');
				if (made != null) {
					rows.add(made);
				}
			}
			result.childrenByObject.put(objectName, rows);
		}
		return result;
	}

	/** Every lookup value a row holds, so the caller can ask which targets still exist. */
	public static Set<Id> lookupsOf(String body) {
		Set<Id> result = new Set<Id>();
		List<SObject> all = new List<SObject>{ recordOf(body) };
		for (List<SObject> rows : childrenOf(body, new Map<String, String>()).values()) {
			all.addAll(rows);
		}
		for (SObject one : all) {
			for (String field : one.getPopulatedFieldsAsMap().keySet()) {
				Object value = one.get(field);
				if (value instanceof Id && field != 'Id') {
					result.add((Id) value);
				}
			}
		}
		return result;
	}

	private static SObject copy(SObject source, String skipField, Set<Id> existing, List<String> dropped, String prefix) {
		Schema.SObjectType type = source.getSObjectType();
		if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()) {
			dropped.add(prefix + 'record');
			return null;
		}
		Map<String, Schema.SObjectField> fields = type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
		SObject made = type.newSObject();
		for (String name : source.getPopulatedFieldsAsMap().keySet()) {
			Schema.SObjectField token = fields.get(name);
			if (name == 'Id' || name == skipField || token == null) {
				continue;
			}
			Schema.DescribeFieldResult field = token.getDescribe();
			Object value = source.get(name);
			if (!field.isCreateable() || value == null) {
				if (value != null && !field.isCalculated() && !field.isAutoNumber() && field.isUpdateable()) {
					dropped.add(prefix + name);
				}
				continue;
			}
			if (value instanceof Id && !existing.contains((Id) value)) {
				dropped.add(prefix + name);
				continue;
			}
			made.put(name, value);
		}
		return made;
	}
}
