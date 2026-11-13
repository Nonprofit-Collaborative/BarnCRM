/**
 * Setup objects BarnCRM ships, looked up by Name or DeveloperName (D-200, N9).
 *
 * In a managed package a shipped permission set, permission set group, custom permission,
 * public group, static resource or email template carries the package's namespace in
 * `NamespacePrefix`, and a subscriber may have one of the same name. A lookup by name alone
 * can pick theirs, or another package's. Every lookup here adds `NamespacePrefix` = this
 * package's namespace (`NamespaceUtil.namespacePrefix`, null with no namespace), so it finds
 * BarnCRM's own and nothing else. Email templates are the one exception: a setting may name an
 * org's own template, so the org's (no prefix) is used when BarnCRM ships none of that name.
 *
 * System mode: these read names and ids of metadata, never records, and the people whose
 * actions need them (a post-install, a guest-site fix, a send) cannot all view setup.
 */
@NamespaceAccessible
public with sharing class SetupObjectSelector {
	/** This package's permission sets (never a profile's) by Name; absent names are left out. */
	@NamespaceAccessible
	public static Map<String, PermissionSet> permissionSets(Set<String> names) {
		String ns = NamespaceUtil.namespacePrefix();
		Map<String, PermissionSet> found = new Map<String, PermissionSet>();
		for (PermissionSet row : [
			SELECT Id, Name, Label
			FROM PermissionSet
			WHERE Name IN :names AND NamespacePrefix = :ns AND IsOwnedByProfile = FALSE
			WITH SYSTEM_MODE
		]) {
			found.put(row.Name, row);
		}
		return found;
	}

	/** This package's permission set of that Name, or null. */
	@NamespaceAccessible
	public static PermissionSet permissionSet(String name) {
		if (String.isNotBlank(name)) {
			for (PermissionSet row : permissionSets(new Set<String>{ name }).values()) {
				return row;
			}
		}
		return null;
	}

	/** This package's permission set groups by DeveloperName; absent names are left out. */
	@NamespaceAccessible
	public static Map<String, PermissionSetGroup> permissionSetGroups(Set<String> names) {
		String ns = NamespaceUtil.namespacePrefix();
		Map<String, PermissionSetGroup> found = new Map<String, PermissionSetGroup>();
		for (PermissionSetGroup row : [
			SELECT Id, DeveloperName, MasterLabel, Description, Status
			FROM PermissionSetGroup
			WHERE DeveloperName IN :names AND NamespacePrefix = :ns
			WITH SYSTEM_MODE
			ORDER BY MasterLabel
		]) {
			found.put(row.DeveloperName, row);
		}
		return found;
	}

	/** The id of this package's custom permission of that DeveloperName, or null. */
	@NamespaceAccessible
	public static Id customPermissionId(String developerName) {
		String ns = NamespaceUtil.namespacePrefix();
		for (CustomPermission row : [
			SELECT Id
			FROM CustomPermission
			WHERE DeveloperName = :developerName AND NamespacePrefix = :ns
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return row.Id;
		}
		return null;
	}

	/** The id of this package's public group of that DeveloperName, or null. */
	@NamespaceAccessible
	public static Id groupId(String developerName) {
		String ns = NamespaceUtil.namespacePrefix();
		for (Group row : [
			SELECT Id
			FROM Group
			WHERE DeveloperName = :developerName AND Type = 'Regular' AND NamespacePrefix = :ns
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return row.Id;
		}
		return null;
	}

	/** This package's static resource of that Name, with its Body, or null. */
	@NamespaceAccessible
	public static StaticResource staticResource(String name) {
		String ns = NamespaceUtil.namespacePrefix();
		for (StaticResource row : [
			SELECT Body
			FROM StaticResource
			WHERE Name = :name AND NamespacePrefix = :ns
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return row;
		}
		return null;
	}

	/** The body of this package's static resource of that Name, as text, or null. */
	@NamespaceAccessible
	public static String staticResourceBody(String name) {
		StaticResource row = staticResource(name);
		return row == null ? null : row.Body.toString();
	}

	/**
	 * Email template ids by DeveloperName: BarnCRM's own, else the org's own (no prefix), never
	 * another package's. Names with neither are left out.
	 *
	 * @param activeOnly true to skip inactive templates
	 */
	@NamespaceAccessible
	public static Map<String, Id> emailTemplateIds(Set<String> developerNames, Boolean activeOnly) {
		String ns = NamespaceUtil.namespacePrefix();
		Map<String, EmailTemplate> chosen = new Map<String, EmailTemplate>();
		for (EmailTemplate row : [
			SELECT Id, DeveloperName, NamespacePrefix, IsActive
			FROM EmailTemplate
			WHERE
				DeveloperName IN :developerNames
				AND (NamespacePrefix = :ns
				OR NamespacePrefix = NULL)
			WITH SYSTEM_MODE
		]) {
			String key = row.DeveloperName.toLowerCase();
			if (
				(activeOnly != true || row.IsActive) &&
				(!chosen.containsKey(key) || ns != null && row.NamespacePrefix == ns)
			) {
				chosen.put(key, row);
			}
		}
		Map<String, Id> ids = new Map<String, Id>();
		for (EmailTemplate row : chosen.values()) {
			ids.put(row.DeveloperName, row.Id);
		}
		return ids;
	}

	/** One email template id, as `emailTemplateIds` finds it, or null. */
	@NamespaceAccessible
	public static Id emailTemplateId(String developerName, Boolean activeOnly) {
		if (String.isNotBlank(developerName)) {
			for (
				Id found : emailTemplateIds(new Set<String>{ developerName }, activeOnly).values()
			) {
				return found;
			}
		}
		return null;
	}
}
