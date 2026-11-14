/**
 * The Record Service quick action (modules-14): one service delivery by hand, with a single
 * Person picker in place of the standard form's Contact and Account fields. Opened from a person
 * (a contact, or a person account) it fills in the person; from an enrollment it fills in the
 * person and the enrollment and offers that program's services. Reads and writes in user mode,
 * so the delivery rules (one person, a person and not an organization, the enrollment filled in)
 * apply as on the standard form, which stays for anyone who prefers it.
 */
public with sharing class RecordServiceController {
	private static final String CONTEXT = 'Record Service action';
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
			CONTEXT,
			'Programs',
			'Programs_Fail_RecordService'
		)
		.showingDml();
	private static final String PERSON_ACCOUNT_FILTER_FIELD = 'IsPersonAccount'; // detection-only: a record picker filter field, sent only after isPersonAccountOrg found person accounts
	/** The most services the form offers when opened from a person. */
	public static final Integer MAX_SERVICES = 200;

	public class Option {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;
	}

	public class Form {
		/** Contact, or Account in a person account org: what the Person picker searches. */
		@AuraEnabled
		public String personObjectApiName = 'Contact';
		@AuraEnabled
		public String personFilterField;
		@AuraEnabled
		public Id personId;
		@AuraEnabled
		public Id enrollmentId;
		@AuraEnabled
		public Id serviceId;
		@AuraEnabled
		public List<Option> services = new List<Option>();
		@AuraEnabled
		public List<Option> attendance = new List<Option>();
		@AuraEnabled
		public Boolean canCreate = false;
		/** The delivery's own field labels, as the org has them. */
		@AuraEnabled
		public String dateLabel = Schema.SObjectType.Service_Delivery__c.fields.Delivery_Date__c.getLabel();
		@AuraEnabled
		public String quantityLabel = Schema.SObjectType.Service_Delivery__c.fields.Quantity__c.getLabel();
	}

	/** The form for the record the action was opened from. */
	@AuraEnabled
	public static Form getForm(Id recordId) {
		try {
			Form form = new Form();
			form.canCreate = Schema.SObjectType.Service_Delivery__c.isCreateable();
			Boolean personAccounts = HouseholdService.isPersonAccountOrg();
			form.personObjectApiName = personAccounts ? 'Account' : 'Contact';
			form.personFilterField = personAccounts ? PERSON_ACCOUNT_FILTER_FIELD : null;
			Id programId;
			Schema.SObjectType type = recordId == null ? null : recordId.getSObjectType();
			if (type == Enrollment__c.SObjectType) {
				for (Enrollment__c enrollment : [
					SELECT Id, Program__c, Contact__c, Account__c
					FROM Enrollment__c
					WHERE Id = :recordId
					WITH USER_MODE
				]) {
					form.enrollmentId = enrollment.Id;
					form.personId = enrollment.Contact__c != null
						? enrollment.Contact__c
						: enrollment.Account__c;
					if (enrollment.Contact__c != null) {
						form.personObjectApiName = 'Contact';
						form.personFilterField = null;
					}
					programId = enrollment.Program__c;
				}
			} else if (type == Contact.SObjectType) {
				form.personId = recordId;
				form.personObjectApiName = 'Contact';
				form.personFilterField = null;
			} else if (type == Account.SObjectType) {
				form.personId = recordId;
				form.personObjectApiName = 'Account';
			}
			addServices(form, programId);
			addAttendance(form);
			return form;
		} catch (Exception failure) {
			throw ERRORS.wrap(failure, CONTEXT, recordId);
		}
	}

	/** Records one delivery and returns its Id. The enrollment is sent only for its own person. */
	@AuraEnabled
	public static Id record(
		Id personId,
		Id serviceId,
		Date deliveryDate,
		String attendance,
		Decimal quantity,
		Id enrollmentId
	) {
		if (
			personId == null ||
			serviceId == null ||
			deliveryDate == null ||
			!ServiceDeliveryService.ATTENDANCE.contains(attendance)
		) {
			throw UserErrors.message(failed());
		}
		try {
			Service_Delivery__c delivery = new Service_Delivery__c(
				Service__c = serviceId,
				Delivery_Date__c = deliveryDate,
				Attendance__c = attendance,
				Quantity__c = ServiceDeliveryService.isAbsence(attendance)
					? 0
					: (quantity == null ? 1 : quantity),
				Enrollment__c = enrollmentId
			);
			if (personId.getSObjectType() == Contact.SObjectType) {
				delivery.Contact__c = personId;
			} else {
				delivery.Account__c = personId;
			}
			Database.insert(delivery, AccessLevel.USER_MODE);
			return delivery.Id;
		} catch (Exception failure) {
			throw ERRORS.wrap(failure, CONTEXT, personId);
		}
	}

	/** The program's active services, or every active service the user can see, by program. */
	private static void addServices(Form form, Id programId) {
		if (programId != null) {
			for (Service__c service : ServiceDeliverySelector.selectActiveServices(programId)) {
				form.services.add(option(service.Name, service.Id));
			}
		} else {
			for (Service__c service : [
				SELECT Id, Name, Program__r.Name
				FROM Service__c
				WHERE Active__c = TRUE
				WITH USER_MODE
				ORDER BY Program__r.Name, Name
				LIMIT :MAX_SERVICES
			]) {
				form.services.add(
					option(service.Program__r.Name + ': ' + service.Name, service.Id)
				);
			}
		}
		if (form.services.size() == 1) {
			form.serviceId = form.services[0].value;
		}
	}

	private static void addAttendance(Form form) {
		for (
			Schema.PicklistEntry entry : Service_Delivery__c.Attendance__c.getDescribe()
				.getPicklistValues()
		) {
			if (entry.isActive()) {
				form.attendance.add(option(entry.getLabel(), entry.getValue()));
			}
		}
	}

	private static Option option(String label, String value) {
		Option option = new Option();
		option.label = label;
		option.value = value;
		return option;
	}

	private static String failed() {
		return BarnHelp.text('Programs', 'Programs_Fail_RecordService');
	}
}
