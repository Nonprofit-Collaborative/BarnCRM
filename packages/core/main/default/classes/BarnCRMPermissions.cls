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
		String ns = NamespaceUtil.namespacePrefix();
		Set<Id> permissionIds = new Map<Id, CustomPermission>(
				[
					SELECT Id
					FROM CustomPermission
					WHERE DeveloperName = :MANAGE_SETTINGS AND NamespacePrefix = :ns
					WITH SYSTEM_MODE
				]
			)
			.keySet();
		return [
				SELECT COUNT()
				FROM PermissionSetAssignment
				WHERE
					Assignee.IsActive = TRUE
					AND PermissionSetId IN (
						SELECT ParentId
						FROM SetupEntityAccess
						WHERE SetupEntityId IN :permissionIds
					)
				WITH SYSTEM_MODE
			] > 0;
	}
}
