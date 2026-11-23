/**
 * The one place that names the custom permission for configuring BarnCRM and checks it.
 *
 * Every settings console page, every module's settings page, and every job an administrator
 * starts asks the same question before it changes anything. Asking it here keeps the name in
 * one place, so a page cannot drift to a different spelling or permission. Each caller still
 * raises its own error, with its own label, when the answer is no.
 */
@NamespaceAccessible
public with sharing class BarnCRMPermissions {
	/** The custom permission that lets a person configure BarnCRM. */
	@NamespaceAccessible
	public static final String MANAGE_SETTINGS = 'Manage_BarnCRM_Settings';

	/** True when the running user may change BarnCRM settings. */
	@NamespaceAccessible
	public static Boolean canManageSettings() {
		return FeatureManagement.checkPermission(MANAGE_SETTINGS);
	}

	/**
	 * True only while Core's package install handler (`CorePostInstall.onInstall`) is running.
	 * Salesforce runs that handler as a special install user who cannot hold Manage BarnCRM
	 * Settings, yet the handler must store the first Features Turned On value (ST-01). Private,
	 * so only this class changes it; the two methods below are the only way, carry no
	 * `@NamespaceAccessible` (ADR-0017, so no other package reaches them), and only the install
	 * handler calls them.
	 */
	private static Boolean installRunning = false;

	/** Called first by `CorePostInstall.onInstall`: saves are allowed until `leaveInstall`. */
	public static void enterInstall() {
		installRunning = true;
	}

	/** Called last by `CorePostInstall.onInstall`, in a finally block. */
	public static void leaveInstall() {
		installRunning = false;
	}

	/** Read by tests: whether the install context is on. */
	@TestVisible
	private static Boolean isInstallRunning() {
		return installRunning;
	}

	/**
	 * True when settings may be saved now: the running user may manage settings, or the package
	 * install handler is running (ST-01). Every other caller needs the permission.
	 */
	public static Boolean canSaveSettings() {
		return installRunning || canManageSettings();
	}

	/**
	 * True when the running user may run Finish Setup and the install entry points
	 * (`BarnInstallCheck`): they may manage settings, or no active user holds that permission
	 * yet and they have Customize Application. The second case is the bootstrap: setup is what
	 * assigns the permission, so an org where it never ran (source copied in, a post-install
	 * that failed) would otherwise have nobody who could press Finish Setup.
	 */
	@NamespaceAccessible
	public static Boolean canRunSetup() {
		if (canManageSettings()) {
			return true;
		}
		Id userId = UserInfo.getUserId();
		Boolean customizes =
			[
				SELECT COUNT()
				FROM PermissionSetAssignment
				WHERE AssigneeId = :userId AND PermissionSet.PermissionsCustomizeApplication = TRUE
				WITH SYSTEM_MODE
			] > 0;
		return customizes && !anyoneManagesSettings();
	}

	/** Set by tests: a test org always has a real admin who may hold the permission. */
	@TestVisible
	private static Boolean anyoneManagesOverride;

	/** True when an active user holds Manage BarnCRM Settings through any permission set. */
	private static Boolean anyoneManagesSettings() {
		if (anyoneManagesOverride != null) {
			return anyoneManagesOverride;
		}
		Id permissionId = SetupObjectSelector.customPermissionId(MANAGE_SETTINGS);
		return [
				SELECT COUNT()
				FROM PermissionSetAssignment
				WHERE
					Assignee.IsActive = TRUE
					AND PermissionSetId IN (
						SELECT ParentId
						FROM SetupEntityAccess
						WHERE SetupEntityId = :permissionId
					)
				WITH SYSTEM_MODE
			] > 0;
	}
}
