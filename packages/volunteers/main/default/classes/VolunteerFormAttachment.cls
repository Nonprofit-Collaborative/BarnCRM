/**
 * Volunteers' side of Core's form seam (ADR-0175 decision 9; ADR-0198 volunteer self-service,
 * decisions 2 and 3). Core finds this class by name (`FormAttachmentExtensions.EXTENSION_CLASSES`);
 * without Forms it is never called.
 *
 * - A shift: its job's Sign-Up Form. Each processed submission books the person Forms matched or
 *   created through `VolunteerBooking`, as the portal does, over target allowed (R-VS4), with the
 *   answers `groupSize` and `groupName` (R-VJ3) and the person written under the record key
 *   `guardian` as the guardian (R-VU11).
 * - A sign-up: the Self-Service Profile Form, behind a signed claim. Each processed submission
 *   writes the answers `availabilityDays`, `availabilityTimes`, `emergencyContactName` and
 *   `emergencyContactPhone` to the Contact the sign-up names, never to a person the answers name
 *   (R-VU10). Blank answers are left out. Written in system mode: the claim proved whose page it is.
 */
@NamespaceAccessible
public with sharing class VolunteerFormAttachment implements FormAttachmentExtension {
	private static final Map<String, Schema.SObjectField> PROFILE = new Map<String, Schema.SObjectField>{
		'availabilityDays' => Contact.Availability_Days__c,
		'availabilityTimes' => Contact.Availability_Times__c,
		'emergencyContactName' => Contact.Emergency_Contact_Name__c,
		'emergencyContactPhone' => Contact.Emergency_Contact_Phone__c
	};
	private static final String LOG_CONTEXT = 'VolunteerFormAttachment';

	@NamespaceAccessible
	public VolunteerFormAttachment() {
		// Built by name from Core (FormAttachmentExtensions), so it needs a public constructor.
	}

	public Boolean handles(Schema.SObjectType contextType) {
		return contextType == Volunteer_Shift__c.SObjectType ||
			contextType == Volunteer_Signup__c.SObjectType;
	}

	/** A sign-up is the person's own record, so its link carries a signed claim. */
	public Boolean signedClaim(Id contextRecordId) {
		return contextRecordId.getSObjectType() == Volunteer_Signup__c.SObjectType;
	}

	public Id formFor(Id contextRecordId) {
		if (contextRecordId.getSObjectType() == Volunteer_Signup__c.SObjectType) {
			return VolunteerSettings.profileFormId();
		}
		for (Volunteer_Shift__c shift : [
			SELECT Volunteer_Job__r.Signup_Form_Key__c
			FROM Volunteer_Shift__c
			WHERE Id = :contextRecordId
			WITH SYSTEM_MODE
		]) {
			try {
				String key = shift.Volunteer_Job__r.Signup_Form_Key__c;
				return String.isBlank(key) ? null : Id.valueOf(key.trim());
			} catch (StringException notAnId) {
				return null;
			}
		}
		return null;
	}

	public void received(FormSubmissionReceipt receipt) {
		if (receipt == null || receipt.contextRecordId == null || receipt.personId == null) {
			return;
		}
		if (receipt.contextRecordId.getSObjectType() == Volunteer_Signup__c.SObjectType) {
			updateProfile(receipt);
			return;
		}
		Id guardian = receipt.recordIds == null ? null : receipt.recordIds.get('guardian');
		if (guardian != null) {
			VolunteerMinors.guardianByPerson.put(receipt.personId, guardian);
		}
		VolunteerBooking.book(
			receipt.personId,
			receipt.contextRecordId,
			groupSize(answer(receipt, 'groupSize')),
			answer(receipt, 'groupName'),
			true
		);
	}

	private static void updateProfile(FormSubmissionReceipt receipt) {
		List<Volunteer_Signup__c> signups = [
			SELECT Contact__c
			FROM Volunteer_Signup__c
			WHERE Id = :receipt.contextRecordId AND Contact__c != NULL
			WITH SYSTEM_MODE
		];
		if (signups.isEmpty()) {
			return;
		}
		Contact person = new Contact(Id = signups[0].Contact__c);
		Boolean changed = false;
		for (String key : PROFILE.keySet()) {
			String value = answer(receipt, key);
			if (String.isNotBlank(value)) {
				person.put(PROFILE.get(key), value);
				changed = true;
			}
		}
		if (changed) {
			Database.SaveResult result = Database.update(person, false, AccessLevel.SYSTEM_MODE);
			if (!result.isSuccess()) {
				ErrorLogger.logMessage(result.getErrors()[0].getMessage(), LOG_CONTEXT, 'Warning');
			}
		}
	}

	/** A whole number from 1 to 50; anything else is 1 (R-VJ3). */
	private static Integer groupSize(String value) {
		try {
			Integer size = String.isBlank(value) ? 1 : Decimal.valueOf(value.trim()).intValue();
			return size >= 1 && size <= 50 ? size : 1;
		} catch (TypeException notANumber) {
			return 1;
		}
	}

	/** An answer as text; a multiple choice answer joined with semicolons, as a multi-select. */
	private static String answer(FormSubmissionReceipt receipt, String key) {
		Object value = receipt.answers == null ? null : receipt.answers.get(key);
		if (value instanceof List<Object>) {
			List<String> parts = new List<String>();
			for (Object part : (List<Object>) value) {
				parts.add(String.valueOf(part));
			}
			return String.join(parts, ';');
		}
		return value == null ? null : String.valueOf(value);
	}
}
