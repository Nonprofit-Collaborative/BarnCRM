/**
 * What the Sign-ups panel on a shift calls (V-02, canonical model Section 29L).
 *
 * Shows how many places the shift has filled, lists its sign-ups, adds one for a person,
 * changes a sign-up's status and closes the shift once it has started, all in user mode. Saves
 * go through the sign-up automation like any other save, so one sign-up per person per shift
 * (R-VU2) and attendance writing the hours (R-VU3, when Attendance Creates Hours is on) apply
 * here too. Anything unexpected is recorded in the Error Log before it is reported (plan
 * Section 7.2).
 */
public with sharing class VolunteerShiftSignupsController {
	private static final String CONTEXT = 'Shift sign-ups panel';
	private static final String STATUS_SHIFT_OPEN = 'Open';
	private static final String STATUS_SHIFT_COMPLETED = 'Completed';
	private static final String STATUS_NO_SHOW = 'No show';
	/** The sign-up statuses still waiting for attendance, which closing a shift can settle. */
	private static final Set<String> OPEN_STATUSES = new Set<String>{ 'Signed up', 'Confirmed' };
	/** The most sign-ups listed: far more than a shift needs, and a bound on the read. */
	public static final Integer MAX_SHOWN = 200;
	/**
	 * The field a record picker filters on to offer person accounts only, sent to the panel as
	 * text and used only in a person account org.
	 */
	private static final String PERSON_ACCOUNT_FILTER_FIELD = 'IsPersonAccount'; // detection-only: a record picker filter field, sent only after isPersonAccountOrg found person accounts

	public class SignupRow {
		@AuraEnabled
		public Id recordId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String personName;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String notes;
	}

	public class Option {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;
	}

	/** The panel's whole state. */
	public class Panel {
		@AuraEnabled
		public String shiftName;
		@AuraEnabled
		public Decimal volunteersNeeded;
		@AuraEnabled
		public Integer slotsFilled = 0;
		@AuraEnabled
		public Decimal slotsRemaining;
		@AuraEnabled
		public List<SignupRow> signups = new List<SignupRow>();
		@AuraEnabled
		public Boolean moreThanShown = false;
		@AuraEnabled
		public Boolean canAdd = false;
		@AuraEnabled
		public Boolean canEdit = false;
		@AuraEnabled
		public Boolean hasPersonAccounts = false;
		@AuraEnabled
		public String personFilterField;
		@AuraEnabled
		public List<Option> statusOptions = new List<Option>();
		/** After a status change: whether an hours entry for the sign-up appeared. */
		@AuraEnabled
		public Boolean hoursWritten = false;
		/** After a status change: whether the sign-up has any hours entry at all. */
		@AuraEnabled
		public Boolean hoursExist = false;
		/** The shift has started: the panel leads with attendance, not the status picker. */
		@AuraEnabled
		public Boolean shiftStarted = false;
		/** The shift is Completed or Cancelled. */
		@AuraEnabled
		public Boolean shiftClosed = false;
		/** The user may close the shift: it has started, is still Open, and they may edit it. */
		@AuraEnabled
		public Boolean canClose = false;
		/** Sign-ups still Signed up or Confirmed, which closing can mark No show. */
		@AuraEnabled
		public Integer openCount = 0;
	}

	/** Not cacheable: the panel changes with every sign-up. */
	@AuraEnabled
	public static Panel getPanel(Id shiftId) {
		if (shiftId == null) {
			throw UserErrors.message(actionFailed());
		}
		try {
			return panelFor(shiftId);
		} catch (Exception failure) {
			throw report(failure, shiftId);
		}
	}

	/** Signs a person up for the shift: a Contact, or a person Account in such an org. */
	@AuraEnabled
	public static Panel addSignup(Id shiftId, Id personId, String status) {
		if (shiftId == null) {
			throw UserErrors.message(actionFailed());
		}
		if (personId == null) {
			throw UserErrors.message(
				BarnHelp.text('Volunteers', 'Volunteers_Signups_PersonRequired')
			);
		}
		Volunteer_Signup__c signup = new Volunteer_Signup__c(Volunteer_Shift__c = shiftId);
		if (String.isNotBlank(status)) {
			signup.Status__c = checkedStatus(status);
		}
		if (personId.getSObjectType() == Contact.SObjectType) {
			signup.Contact__c = personId;
		} else {
			signup.Account__c = personId;
		}
		try {
			Database.insert(new List<Volunteer_Signup__c>{ signup }, true, AccessLevel.USER_MODE);
			return panelFor(shiftId);
		} catch (Exception failure) {
			throw report(failure, shiftId);
		}
	}

	/**
	 * Changes a sign-up's status. Marking it Attended writes its hours through the sign-up
	 * automation when the setting is on, and the panel says whether an entry appeared.
	 */
	@AuraEnabled
	public static Panel setStatus(Id signupId, String status) {
		if (signupId == null || String.isBlank(status)) {
			throw UserErrors.message(actionFailed());
		}
		String wanted = checkedStatus(status);
		try {
			Volunteer_Signup__c signup = VolunteerSignupSelector.selectById(signupId);
			if (signup == null) {
				throw UserErrors.message(actionFailed());
			}
			Integer hoursBefore = VolunteerSignupSelector.countHoursFor(signupId);
			Database.update(
				new List<Volunteer_Signup__c>{
					new Volunteer_Signup__c(Id = signupId, Status__c = wanted)
				},
				true,
				AccessLevel.USER_MODE
			);
			Panel panel = panelFor(signup.Volunteer_Shift__c);
			Integer hoursAfter = VolunteerSignupSelector.countHoursFor(signupId);
			panel.hoursWritten = hoursAfter > hoursBefore;
			panel.hoursExist = hoursAfter > 0;
			return panel;
		} catch (AuraHandledException refused) {
			throw refused;
		} catch (Exception failure) {
			throw report(failure, signupId);
		}
	}

	/**
	 * Closes a shift that has started (modules-12): marks its sign-ups still Signed up or
	 * Confirmed as No show when asked, then sets the shift's Status to Completed. Both saves run
	 * in user mode through the usual automation, in one transaction, so a refusal changes
	 * nothing.
	 */
	@AuraEnabled
	public static Panel closeShift(Id shiftId, Boolean markNoShow) {
		if (shiftId == null) {
			throw UserErrors.message(actionFailed());
		}
		Savepoint before = Database.setSavepoint();
		try {
			Volunteer_Shift__c shift = VolunteerSignupSelector.selectShift(shiftId);
			if (shift == null || shift.Status__c != STATUS_SHIFT_OPEN) {
				throw UserErrors.message(actionFailed());
			}
			if (markNoShow == true) {
				List<Volunteer_Signup__c> open = VolunteerSignupSelector.selectOpenForShift(
					shiftId,
					OPEN_STATUSES
				);
				for (Volunteer_Signup__c signup : open) {
					signup.Status__c = STATUS_NO_SHOW;
				}
				Database.update(open, true, AccessLevel.USER_MODE);
			}
			Database.update(
				new List<Volunteer_Shift__c>{
					new Volunteer_Shift__c(Id = shiftId, Status__c = STATUS_SHIFT_COMPLETED)
				},
				true,
				AccessLevel.USER_MODE
			);
			return panelFor(shiftId);
		} catch (Exception failure) {
			Database.rollback(before);
			throw report(failure, shiftId);
		}
	}

	// ------------------------------------------------------------------------------ helpers

	/** The panel's failure message, from the Volunteers help catalog (modules-1). */
	private static String actionFailed() {
		return BarnHelp.text('Volunteers', 'Volunteers_Signups_ActionFailed');
	}

	private static Panel panelFor(Id shiftId) {
		Volunteer_Shift__c shift = VolunteerSignupSelector.selectShift(shiftId);
		if (shift == null) {
			throw UserErrors.message(actionFailed());
		}
		Panel panel = new Panel();
		panel.shiftName = shift.Name;
		panel.volunteersNeeded = shift.Volunteers_Needed__c;
		panel.slotsFilled = VolunteerSignupSelector.countFilled(shiftId);
		panel.slotsRemaining = shift.Volunteers_Needed__c == null
			? null
			: shift.Volunteers_Needed__c - panel.slotsFilled;
		panel.shiftStarted = shift.Start_Time__c != null && shift.Start_Time__c <= Datetime.now();
		panel.shiftClosed = shift.Status__c != null && shift.Status__c != STATUS_SHIFT_OPEN;

		List<Volunteer_Signup__c> found = VolunteerSignupSelector.selectForShift(
			shiftId,
			MAX_SHOWN + 1
		);
		panel.moreThanShown = found.size() > MAX_SHOWN;
		for (Integer i = 0; i < found.size() && i < MAX_SHOWN; i++) {
			panel.signups.add(rowFor(found[i]));
		}
		panel.openCount = VolunteerSignupSelector.countOpen(shiftId, OPEN_STATUSES);

		Schema.DescribeSObjectResult describe = Volunteer_Signup__c.SObjectType.getDescribe(
			SObjectDescribeOptions.DEFERRED
		);
		panel.canAdd = describe.isCreateable();
		panel.canEdit = describe.isUpdateable();
		panel.canClose =
			panel.shiftStarted &&
			!panel.shiftClosed &&
			Volunteer_Shift__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
				.isUpdateable();
		panel.hasPersonAccounts = HouseholdService.isPersonAccountOrg();
		panel.personFilterField = panel.hasPersonAccounts ? PERSON_ACCOUNT_FILTER_FIELD : null;
		for (Schema.PicklistEntry entry : statusEntries()) {
			Option option = new Option();
			option.label = entry.getLabel();
			option.value = entry.getValue();
			panel.statusOptions.add(option);
		}
		return panel;
	}

	private static SignupRow rowFor(Volunteer_Signup__c signup) {
		SignupRow row = new SignupRow();
		row.recordId = signup.Id;
		row.name = signup.Name;
		row.status = signup.Status__c;
		row.notes = signup.Notes__c;
		if (signup.Contact__c != null) {
			row.personName = signup.Contact__r == null ? null : signup.Contact__r.Name;
		} else {
			row.personName = signup.Account__r == null ? null : signup.Account__r.Name;
		}
		return row;
	}

	private static List<Schema.PicklistEntry> statusEntries() {
		List<Schema.PicklistEntry> active = new List<Schema.PicklistEntry>();
		for (
			Schema.PicklistEntry entry : Volunteer_Signup__c.Status__c.getDescribe()
				.getPicklistValues()
		) {
			if (entry.isActive()) {
				active.add(entry);
			}
		}
		return active;
	}

	/** A status the picklist offers, or a refusal: the field is restricted anyway. */
	private static String checkedStatus(String status) {
		for (Schema.PicklistEntry entry : statusEntries()) {
			if (entry.getValue() == status) {
				return entry.getValue();
			}
		}
		throw UserErrors.message(actionFailed());
	}

	/**
	 * A save a rule refused (a second sign-up, a person the user may not book) is passed on in
	 * its own words; anything else is logged first.
	 */
	private static AuraHandledException report(Exception failure, Id recordId) {
		if (failure instanceof AuraHandledException) {
			return (AuraHandledException) failure;
		}
		if (failure instanceof DmlException) {
			return UserErrors.message(((DmlException) failure).getDmlMessage(0));
		}
		ErrorLogger.log(failure, CONTEXT, recordId);
		return UserErrors.message(actionFailed());
	}
}
