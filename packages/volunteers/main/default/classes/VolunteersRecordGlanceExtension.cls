/**
 * The Volunteers card on Core's person pages (modules-21, ADR-0167): the person's volunteer
 * status, hours this year and in all, and last volunteer date, the Volunteer Profile fields,
 * labelled from the fields, with a button to their volunteer hours. Registered in Core's
 * `RecordGlanceExtensions`; Core holds no reference to Volunteers.
 *
 * Read with the viewer's own access: a field the viewer cannot read is left off, and there is
 * no card for anything but a contact, for someone who can read none of the fields, or for a
 * person who has no volunteer status and no hours.
 */
@NamespaceAccessible
public with sharing class VolunteersRecordGlanceExtension implements RecordGlanceExtension {
	@TestVisible
	private static final String KEY = 'volunteers';
	/** The Volunteer Hours tab's icon. */
	private static final String ICON = 'custom:custom3';

	/** Built by name from Core. */
	@NamespaceAccessible
	public VolunteersRecordGlanceExtension() {
		return;
	}

	public RecordGlance.Card glance(Id recordId) {
		if (recordId == null || recordId.getSObjectType() != Contact.SObjectType) {
			return null;
		}
		List<Schema.SObjectField> readable = readableFields();
		if (readable.isEmpty()) {
			return null;
		}
		List<String> columns = new List<String>();
		for (Schema.SObjectField field : readable) {
			String name = String.valueOf(field);
			columns.add(field == Contact.Volunteer_Status__c ? 'toLabel(' + name + ')' : name);
		}
		List<Contact> found = Database.queryWithBinds(
			'SELECT ' + String.join(columns, ', ') + ' FROM Contact WHERE Id = :recordId',
			new Map<String, Object>{ 'recordId' => recordId },
			AccessLevel.USER_MODE
		);
		if (found.isEmpty()) {
			return null;
		}
		Contact person = found[0];
		Boolean volunteers = false;
		RecordGlance.Card card = new RecordGlance.Card(KEY, Label.Volunteers_Glance_Title, ICON);
		for (Schema.SObjectField field : readable) {
			Object value = person.get(field);
			String label = field.getDescribe().getLabel();
			if (field == Contact.Volunteer_Status__c) {
				card.addText(label, (String) value);
			} else if (field == Contact.Last_Volunteer_Date__c) {
				card.addDate(label, (Date) value);
			} else {
				card.addNumber(label, (Decimal) value);
			}
			volunteers = volunteers || saysSomething(value);
		}
		if (!volunteers) {
			return null;
		}
		if (Schema.SObjectType.Volunteer_Hours__c.isAccessible()) {
			card.addRelatedListAction(
				Label.Volunteers_Glance_ViewHours,
				recordId,
				Volunteer_Hours__c.Contact__c
			);
		}
		return card;
	}

	/** True for a status, a date or hours above zero: something that makes the person a volunteer. */
	private static Boolean saysSomething(Object value) {
		if (value instanceof Decimal) {
			return (Decimal) value != 0;
		}
		return value instanceof String ? String.isNotBlank((String) value) : value != null;
	}

	/** The card's fields, in the card's order, that the viewer may read. */
	private static List<Schema.SObjectField> readableFields() {
		List<Schema.SObjectField> readable = new List<Schema.SObjectField>();
		for (
			Schema.SObjectField field : new List<Schema.SObjectField>{
				Contact.Volunteer_Status__c,
				Contact.Volunteer_Hours_This_Year__c,
				Contact.Volunteer_Hours_Total__c,
				Contact.Last_Volunteer_Date__c
			}
		) {
			if (field.getDescribe().isAccessible()) {
				readable.add(field);
			}
		}
		return readable;
	}
}
