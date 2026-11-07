/**
 * The Core seam a module uses to show a record of an optional module that it holds by record
 * identifier as text, such as the Giving gift or commitment, or the Funders award, an event
 * sponsorship is tied to (EV-09, ADR-NEXT events sponsorship).
 *
 * The module names no object of another module: it stores the identifier, and this class turns
 * it into a label. Only the records of the objects listed in `SUPPORTED` resolve, and only when
 * that object is in the org and the viewing person may read it (user mode), so with Giving or
 * Funders absent, or the record unreadable or deleted, the identifier simply has no label and
 * the caller shows nothing. Nothing here throws for a bad identifier.
 */
@NamespaceAccessible
public with sharing class LinkedRecords {
	/** The optional modules' objects a link may name, by API name. */
	@TestVisible
	private static List<String> supported = new List<String>{
		'Gift__c',
		'Commitment__c',
		'Grant__c'
	};

	/** What a caller shows for one linked record. */
	@NamespaceAccessible
	public class Link {
		/** The record's name. */
		@NamespaceAccessible
		public String label;
		/** The object's label, such as Gift. */
		@NamespaceAccessible
		public String objectLabel;
	}

	/**
	 * The label of each readable linked record, by identifier. An identifier that is blank, not an
	 * identifier, of another object, of an object not in the org, or of a record the person cannot
	 * read is left out.
	 *
	 * @param recordIds the identifiers as stored, text
	 * @return links by the identifier as given
	 */
	@NamespaceAccessible
	public static Map<String, Link> resolve(List<String> recordIds) {
		Map<String, Link> found = new Map<String, Link>();
		Map<Schema.SObjectType, Map<String, Id>> byType = new Map<Schema.SObjectType, Map<String, Id>>();
		Map<String, Schema.SObjectType> present = supportedTypes();
		for (String text : recordIds == null ? new List<String>() : recordIds) {
			Id recordId = asId(text);
			if (
				recordId == null ||
				!present.containsKey(recordId.getSObjectType().getDescribe().getName())
			) {
				continue;
			}
			Schema.SObjectType type = recordId.getSObjectType();
			if (!byType.containsKey(type)) {
				byType.put(type, new Map<String, Id>());
			}
			byType.get(type).put(text, recordId);
		}
		for (Schema.SObjectType type : byType.keySet()) {
			Schema.DescribeSObjectResult described = type.getDescribe();
			if (!described.isAccessible()) {
				continue;
			}
			Set<Id> ids = new Set<Id>(byType.get(type).values());
			String query =
				'SELECT Id, Name FROM ' +
				String.escapeSingleQuotes(described.getName()) +
				' WHERE Id IN :ids LIMIT 200';
			Map<Id, String> names = new Map<Id, String>();
			for (SObject row : Database.query(query, AccessLevel.USER_MODE)) {
				names.put(row.Id, (String) row.get('Name'));
			}
			for (String text : byType.get(type).keySet()) {
				Id recordId = byType.get(type).get(text);
				if (names.containsKey(recordId)) {
					Link link = new Link();
					link.label = names.get(recordId);
					link.objectLabel = described.getLabel();
					found.put(text, link);
				}
			}
		}
		return found;
	}

	/** The supported objects that are in this org, by API name. */
	private static Map<String, Schema.SObjectType> supportedTypes() {
		Map<String, Schema.SObjectType> present = new Map<String, Schema.SObjectType>();
		for (String apiName : supported) {
			Schema.SObjectType type = NamespaceUtil.packagedObjectType(apiName);
			if (type != null) {
				present.put(type.getDescribe().getName(), type);
			}
		}
		return present;
	}

	private static Id asId(String text) {
		if (String.isBlank(text)) {
			return null;
		}
		try {
			return Id.valueOf(text.trim());
		} catch (Exception notAnId) {
			return null;
		}
	}
}
