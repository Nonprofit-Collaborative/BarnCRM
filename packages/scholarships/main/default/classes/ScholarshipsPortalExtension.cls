/**
 * The applicant portal's actions (PB-06, SG-07; ADR-0185 decision 9; ADR-0204
 * `0204-scholarships-outbound-grants-module.md` decision 12): `Scholarships.Apply` on an open
 * cycle starts a Draft application for the verified person, with their signed form link where it
 * can be made now (the nightly run fills any left blank); `Scholarships.Withdraw` withdraws one of
 * their own not yet decided; `Scholarships.AcceptAward` accepts one of their own Offered awards.
 * Core finds this class by name (`PortalActionExtensions.EXTENSION_CLASSES`).
 *
 * `without sharing` and system mode (ADR-0021): the portal's integration user has no object
 * access. Writes name only the verified person and touch only that person's own records.
 */
@NamespaceAccessible
public without sharing class ScholarshipsPortalExtension implements PortalActionExtension {
	public static final String APPLY = 'Scholarships.Apply';
	public static final String WITHDRAW = 'Scholarships.Withdraw';
	public static final String ACCEPT = 'Scholarships.AcceptAward';

	@NamespaceAccessible
	public ScholarshipsPortalExtension() {
		return;
	}

	public Set<String> actionNames() {
		return new Set<String>{ APPLY, WITHDRAW, ACCEPT };
	}

	public String run(String actionName, Id personId, Id recordId) {
		if (personId == null || recordId == null) {
			throw new System.IllegalArgumentException('A person and a record are needed');
		}
		if (actionName == APPLY) {
			return apply(personId, recordId);
		}
		if (actionName == WITHDRAW) {
			return withdraw(personId, recordId);
		}
		if (actionName == ACCEPT) {
			return accept(personId, recordId);
		}
		throw new System.IllegalArgumentException('Unknown action ' + actionName);
	}

	private static String apply(Id personId, Id cycleId) {
		List<Award_Cycle__c> cycles = [
			SELECT Id, Status__c, Close_Date__c
			FROM Award_Cycle__c
			WHERE Id = :cycleId
			WITH SYSTEM_MODE
		];
		if (cycles.isEmpty()) {
			return BarnHelp.text('Scholarships', 'Scholarships_Portal_Closed');
		}
		Award_Cycle__c cycle = cycles[0];
		if (
			cycle.Status__c != 'Open' ||
			(cycle.Close_Date__c != null &&
			cycle.Close_Date__c < Date.today())
		) {
			return BarnHelp.text('Scholarships', 'Scholarships_Portal_Closed');
		}
		Integer current = [
			SELECT COUNT()
			FROM Award_Application__c
			WHERE Cycle__c = :cycleId AND Contact__c = :personId AND Status__c != 'Withdrawn'
			WITH SYSTEM_MODE
		];
		if (current > 0) {
			return BarnHelp.text('Scholarships', 'Scholarships_Portal_AlreadyApplied');
		}
		Award_Application__c draft = new Award_Application__c(
			Cycle__c = cycleId,
			Contact__c = personId,
			Status__c = 'Draft'
		);
		insert as system draft;
		try {
			draft.Form_Link__c = ScholarshipFormAttachment.linkFor(draft.Id);
			if (draft.Form_Link__c != null) {
				update as system new Award_Application__c(
					Id = draft.Id,
					Form_Link__c = draft.Form_Link__c
				);
			}
		} catch (Exception notNow) {
			ErrorLogger.log(notNow, 'ScholarshipsPortalExtension.apply', draft.Id);
		}
		return BarnHelp.text('Scholarships', 'Scholarships_Portal_Applied');
	}

	private static String withdraw(Id personId, Id applicationId) {
		List<Award_Application__c> rows = [
			SELECT Id, Status__c
			FROM Award_Application__c
			WHERE Id = :applicationId AND Contact__c = :personId
			WITH SYSTEM_MODE
		];
		if (rows.isEmpty()) {
			throw new System.QueryException('The application is not this person\'s');
		}
		if (
			rows[0].Status__c == 'Awarded' ||
			rows[0].Status__c == 'Declined' ||
			rows[0].Status__c == 'Ineligible' ||
			rows[0].Status__c == 'Withdrawn'
		) {
			return BarnHelp.text('Scholarships', 'Scholarships_Portal_CannotWithdraw');
		}
		update as system new Award_Application__c(Id = applicationId, Status__c = 'Withdrawn');
		return BarnHelp.text('Scholarships', 'Scholarships_Portal_Withdrawn');
	}

	private static String accept(Id personId, Id awardId) {
		List<Award__c> rows = [
			SELECT Id, Status__c
			FROM Award__c
			WHERE Id = :awardId AND Contact__c = :personId
			WITH SYSTEM_MODE
		];
		if (rows.isEmpty()) {
			throw new System.QueryException('The award is not this person\'s');
		}
		if (rows[0].Status__c != 'Offered') {
			return BarnHelp.text('Scholarships', 'Scholarships_Award_NotOffered');
		}
		update as system new Award__c(
			Id = awardId,
			Status__c = 'Accepted',
			Accepted_Date__c = Date.today()
		);
		return BarnHelp.text('Scholarships', 'Scholarships_Portal_Accepted');
	}
}
