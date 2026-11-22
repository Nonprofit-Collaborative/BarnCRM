/**
 * The system mode writes behind the Automation page: the org default `BarnCRM_Automation_Control__c`
 * record for the automation pause (`Paused_Until__c`), the Automation Setting rows materialized from the shipped
 * registry (and an org's own listed flow's row, removed again), and the BarnCRM Automation
 * Control rows (canonical model R-A8: a custom setting takes no permission a BarnCRM Admin
 * could hold; `AutomationControlSettingService` checks the permission and the owner first).
 *
 * ADR-0021 (system mode writes for package owned data) is the authority for this class and
 * names it as one of its writers. Two writes, each for its own reason:
 *
 * 1. The pause. A protected hierarchy custom setting takes no object or field permissions in a
 *    subscriber org: there is no way to grant a BarnCRM Admin field access to it. Writing the
 *    pause setting in user mode therefore fails for everyone who is not a system administrator,
 *    which is most of the people this feature is for. Nothing is read here and one field is
 *    written: the caller passes a datetime it computed from a number of hours it has already
 *    validated.
 * 2. The switch rows. Each row carries `Always_Runs__c`, which no packaged permission set may
 *    edit (ADR-0024: an automation that enforces a rule must not be made switchable by editing
 *    its row), so a user mode insert of a complete row is refused for everyone. The rows are
 *    written by the post-install scripts, where no permission set is assigned yet, and by the
 *    Health Check fix. Every value is copied from the package's own shipped registry by
 *    `AutomationControl`; nothing an administrator types reaches this class. The one row not
 *    from the registry, a generated rollup trigger's switch (`AutomationControl.ensureSwitch`,
 *    ADR-0138), is built from describe and labels, with Always Runs false, after the same
 *    permission check.
 *
 * The permission is enforced before this class is reached: `AutomationControl` writes the pause
 * only after `FeatureManagement.checkPermission('Manage_BarnCRM_Settings')` passes, and the
 * Health Check fix checks the same permission in `HealthCheckController` before it asks for the
 * switch rows. The post-install scripts run as the platform's install user, which the platform
 * itself authorizes.
 */
public without sharing class AutomationSettingsWriter {
	/**
	 * Locks the organization-level Automation Control row until this transaction ends, so two
	 * pauses or a pause and the resume job take turns reading and saving the pause end.
	 */
	public static void lockPause() {
		Id orgId = UserInfo.getOrganizationId();
		List<BarnCRM_Automation_Control__c> rows = [
			SELECT Id
			FROM BarnCRM_Automation_Control__c
			WHERE SetupOwnerId = :orgId
			WITH SYSTEM_MODE
			LIMIT 1
			FOR UPDATE
		];
		lockedControlId = rows.isEmpty() ? null : rows[0].Id;
	}

	private static Id lockedControlId;

	/**
	 * Saves the pause end on the organization-level Automation Control row (ADR-0238 settings as
	 * custom metadata, decision 7), creating it with its shipped checkboxes when the org has
	 * none. A pause the legacy BarnCRM Settings row still holds is cleared, so it cannot come
	 * back once this one ends.
	 */
	public static void savePausedUntil(Datetime pausedUntil) {
		BarnCRM_Automation_Control__c row = lockedControlId != null
			? new BarnCRM_Automation_Control__c(Id = lockedControlId)
			: new BarnCRM_Automation_Control__c(
					SetupOwnerId = UserInfo.getOrganizationId(),
					Pause_All__c = false,
					Bypass__c = false
				);
		row.Paused_Until__c = pausedUntil;
		upsert as system row;
		lockedControlId = row.Id;
		if (BarnCRM_Settings__c.getOrgDefaults()?.Automation_Paused_Until__c != null) {
			OrgSettingsSystemWriter.save(
				new Map<Schema.SObjectField, Object>{ BarnCRM_Settings__c.Automation_Paused_Until__c => null }
			);
		}
	}

	/** Inserts switch rows materialized from the shipped registry, or a generated trigger's. */
	public static void insertSwitches(List<Automation_Setting__c> switches) {
		if (switches == null || switches.isEmpty()) {
			return;
		}
		Database.insert(switches, AccessLevel.SYSTEM_MODE);
	}

	/**
	 * Deletes the switch row of an org's own listed flow (R-A8). The caller has checked the
	 * permission and that the row is a `Flow:` row that is not a package default.
	 */
	public static void deleteSwitch(Id switchId) {
		Database.delete(switchId, true, AccessLevel.SYSTEM_MODE);
	}

	/**
	 * Saves one BarnCRM Automation Control row (R-A8): a custom setting takes no object or field
	 * permission a BarnCRM Admin could hold. The caller has checked the permission and that the
	 * owner is this org, a Profile or a User; only the two checkboxes are set.
	 */
	public static void saveControl(BarnCRM_Automation_Control__c row) {
		upsert as system row;
	}

	/** Deletes one profile or user BarnCRM Automation Control row, after the same checks. */
	public static void deleteControl(Id rowId) {
		Database.delete(rowId, true, AccessLevel.SYSTEM_MODE);
	}
}
