/**
 * Programs at a Glance (D-200 R1): the card Programs adds to Core's Contact and Account record
 * pages through the record glance seam (ADR-0167), so staff see a person's open enrollments and
 * last service, and enroll them or record a service, without switching to BarnCRM Programs.
 *
 * It reads what the person's Programs card reads (`PersonEnrollmentsController`), with the
 * viewer's own access: someone who cannot read enrollments, and any household or
 * organization, gets no card. Enroll shows only to someone who can create an enrollment, and
 * Record Service only to someone who can create a service delivery.
 */
@NamespaceAccessible
public with sharing class ProgramsRecordGlanceExtension implements RecordGlanceExtension {
	@TestVisible
	private static final String RECORD_SERVICE_TAB = 'Record_Service';

	@NamespaceAccessible
	public ProgramsRecordGlanceExtension() {
		// Built by name from Core (RecordGlanceExtensions), so it needs a public constructor.
	}

	public RecordGlance.Card glance(Id recordId) {
		if (recordId == null) {
			return null;
		}
		PersonEnrollmentsController.PersonEnrollments person = PersonEnrollmentsController.getEnrollments(
			recordId
		);
		if (person == null || person.canSee != true) {
			return null;
		}
		Integer open = 0;
		for (PersonEnrollmentsController.Row row : person.enrollments) {
			if (row.isOpen == true) {
				open++;
			}
		}
		RecordGlance.Card card = new RecordGlance.Card(
				'programs',
				Label.Programs_Glance_Title,
				'custom:custom60'
			)
			.addNumber(BarnHelp.text('Programs', 'Programs_Glance_OpenEnrollments'), open)
			.addDate(
				BarnHelp.text('Programs', 'Programs_Glance_LastService'),
				person.lastServiceDate
			);
		if (Schema.SObjectType.Enrollment__c.isCreateable()) {
			card.addAction(Label.Programs_Enroll, enrollReference(recordId));
		}
		if (Schema.SObjectType.Service_Delivery__c.isCreateable()) {
			card.addAction(Label.Programs_RecordService_Title, recordServiceReference(recordId));
		}
		return card;
	}

	/** A new enrollment with the person filled in: the contact, or the person account. */
	@TestVisible
	private static Map<String, Object> enrollReference(Id personId) {
		Schema.SObjectField personField = personId.getSObjectType() == Contact.SObjectType
			? Enrollment__c.Contact__c
			: Enrollment__c.Account__c;
		return new Map<String, Object>{
			'type' => 'standard__objectPage',
			'attributes' => new Map<String, Object>{
				'objectApiName' => Schema.SObjectType.Enrollment__c.getName(),
				'actionName' => 'new'
			},
			'state' => new Map<String, Object>{
				'defaultFieldValues' => personField.getDescribe().getName() +
				'=' +
				personId
			}
		};
	}

	/** The Record Service tab with the person (`c__personId`), the contract with recordService. */
	@TestVisible
	private static Map<String, Object> recordServiceReference(Id personId) {
		return new Map<String, Object>{
			'type' => 'standard__navItemPage',
			'attributes' => new Map<String, Object>{
				'apiName' => NamespaceUtil.prefix() + RECORD_SERVICE_TAB
			},
			'state' => new Map<String, Object>{ NamespaceUtil.stateKey('personId') => personId }
		};
	}
}
