/**
 * Volunteering at a Glance (D-200 R1): the card Volunteers adds to Core's Contact and Account
 * record pages through the record glance seam (ADR-0167), so staff see a person's hours this
 * year and last volunteer date, and log hours, without switching to BarnCRM Volunteers.
 *
 * Read with the viewer's own access: someone who cannot read volunteer hours or those fields
 * gets no card, and Log Hours shows only to someone who can create hours. A household or an
 * organization gets no card (hours belong to a person). The figures are the rollups already
 * on the record, so nothing is counted here.
 */
@NamespaceAccessible
public with sharing class VolunteersRecordGlanceExtension implements RecordGlanceExtension {
	@TestVisible
	private static final String LOG_HOURS_TAB = 'Log_Hours';

	@NamespaceAccessible
	public VolunteersRecordGlanceExtension() {
		// Built by name from Core (RecordGlanceExtensions), so it needs a public constructor.
	}

	public RecordGlance.Card glance(Id recordId) {
		if (recordId == null || !Schema.SObjectType.Volunteer_Hours__c.isAccessible()) {
			return null;
		}
		Schema.SObjectType objectType = recordId.getSObjectType();
		List<SObject> rows;
		try {
			if (objectType == Contact.SObjectType) {
				rows = [
					SELECT Id, Volunteer_Hours_This_Year__c, Last_Volunteer_Date__c
					FROM Contact
					WHERE Id = :recordId
					WITH USER_MODE
				];
			} else if (
				objectType == Account.SObjectType &&
				!VolunteerLetterSelector.personAccounts(new Set<Id>{ recordId }).isEmpty()
			) {
				rows = [
					SELECT Id, Volunteer_Hours_This_Year__c, Last_Volunteer_Date__c
					FROM Account
					WHERE Id = :recordId
					WITH USER_MODE
				];
			}
		} catch (QueryException noAccess) {
			// The viewer cannot read the volunteer fields: no card, rather than an error.
			return null;
		}
		return rows == null || rows.isEmpty() ? null : card(rows[0], objectType);
	}

	@TestVisible
	private static RecordGlance.Card card(SObject person, Schema.SObjectType objectType) {
		Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
		Decimal hours = (Decimal) person.get('Volunteer_Hours_This_Year__c');
		RecordGlance.Card card = new RecordGlance.Card(
				'volunteers',
				Label.Volunteers_Glance_Title,
				'custom:custom3'
			)
			.addNumber(
				NamespaceUtil.field(fields, 'Volunteer_Hours_This_Year__c')
					.getDescribe()
					.getLabel(),
				hours == null ? 0 : hours
			)
			.addDate(
				NamespaceUtil.field(fields, 'Last_Volunteer_Date__c').getDescribe().getLabel(),
				(Date) person.get('Last_Volunteer_Date__c')
			);
		if (Schema.SObjectType.Volunteer_Hours__c.isCreateable()) {
			card.addAction(
				Label.Volunteers_LogHours_Title,
				logHoursReference((Id) person.get('Id'))
			);
		}
		return card;
	}

	/** The Log Hours tab with the person (`c__personId`), the contract with volunteerLogHours. */
	@TestVisible
	private static Map<String, Object> logHoursReference(Id personId) {
		return new Map<String, Object>{
			'type' => 'standard__navItemPage',
			'attributes' => new Map<String, Object>{
				'apiName' => NamespaceUtil.prefix() + LOG_HOURS_TAB
			},
			'state' => new Map<String, Object>{ NamespaceUtil.stateKey('personId') => personId }
		};
	}
}
