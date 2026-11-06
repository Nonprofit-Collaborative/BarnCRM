/**
 * The Programs card on Core's person pages (modules-21, ADR-0167): how many programs the person
 * is enrolled in now, their last service and how many services they attended, with a button to
 * their enrollments. The figures are the person's Programs card's (`PersonEnrollmentsController`),
 * so the two never disagree. Registered in Core's `RecordGlanceExtensions`; Core holds no
 * reference to Programs.
 *
 * Read with the viewer's own access: no card for an organization or household, for someone who
 * cannot read enrollments, or for a person with no enrollment and no service.
 */
@NamespaceAccessible
public with sharing class ProgramsRecordGlanceExtension implements RecordGlanceExtension {
	@TestVisible
	private static final String KEY = 'programs';
	/** The icon of the person's Programs card, the Enrollment tab's. */
	private static final String ICON = 'custom:custom60';

	/** Built by name from Core. */
	@NamespaceAccessible
	public ProgramsRecordGlanceExtension() {
		return;
	}

	public RecordGlance.Card glance(Id recordId) {
		PersonEnrollmentsController.PersonEnrollments person = PersonEnrollmentsController.getEnrollments(
			recordId
		);
		if (!person.canSee || (person.enrollments.isEmpty() && person.servicesAttended == 0)) {
			return null;
		}
		Integer open = 0;
		for (PersonEnrollmentsController.Row row : person.enrollments) {
			if (row.isOpen) {
				open++;
			}
		}
		RecordGlance.Card card = new RecordGlance.Card(KEY, Label.Programs_Glance_Title, ICON)
			.addNumber(Label.Programs_Glance_OpenEnrollments, open)
			.addDate(Label.Programs_Glance_LastService, person.lastServiceDate)
			.addNumber(Label.Programs_Glance_ServicesAttended, person.servicesAttended);
		Schema.SObjectField lookup = recordId.getSObjectType() == Contact.SObjectType
			? Enrollment__c.Contact__c
			: Enrollment__c.Account__c;
		return card.addRelatedListAction(Label.Programs_Glance_ViewEnrollments, recordId, lookup);
	}
}
