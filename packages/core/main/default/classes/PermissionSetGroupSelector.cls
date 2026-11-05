/**
 * Reads the packaged permission set groups that back the roles on the Access page.
 *
 * Groups are always looked up by DeveloperName, never by Id, so that nothing in the
 * package depends on an Id that differs from org to org.
 */
public with sharing class PermissionSetGroupSelector {
	/**
	 * Injected by the tests, and never set anywhere else, so a subscriber org always runs the
	 * query below.
	 *
	 * The install path has to be provable in the state a real org is in during the minutes
	 * after an install, when the platform is still calculating the packaged groups and refuses
	 * to assign one. No test can produce that state: Status is written by the platform, Apex
	 * cannot assign it, and Test.calculatePermissionSetGroup only ever moves a group forwards
	 * to Updated. Simply not calling that method does not produce it either, because in an org
	 * where the metadata is already deployed the groups are Updated before the test starts.
	 * So the tests hand the group they want the install code to see to this field instead.
	 */
	@TestVisible
	private static PermissionSetGroup systemModeOverride;

	/**
	 * Returns the permission set groups whose DeveloperName is in the given set.
	 *
	 * @param developerNames the DeveloperName values to look for
	 * @return the matching groups, ordered by label; an empty list when nothing matches
	 */
	public List<PermissionSetGroup> selectByDeveloperNames(Set<String> developerNames) {
		if (developerNames == null || developerNames.isEmpty()) {
			return new List<PermissionSetGroup>();
		}
		return [
			SELECT Id, DeveloperName, MasterLabel, Description, Status
			FROM PermissionSetGroup
			WHERE DeveloperName IN :developerNames
			WITH USER_MODE
			ORDER BY MasterLabel
		];
	}

	/**
	 * Returns a single permission set group by DeveloperName, in system mode.
	 *
	 * Used only by the post-install script, which runs as a platform user with no session
	 * and no permission set of its own, so user mode has nothing to enforce against. Every
	 * other caller uses the user mode methods above.
	 *
	 * @param developerName the DeveloperName to look for
	 * @return the group, or null when the org does not have it
	 */
	public PermissionSetGroup selectByDeveloperNameInSystemMode(String developerName) {
		if (String.isBlank(developerName)) {
			return null;
		}
		if (systemModeOverride != null) {
			return systemModeOverride;
		}
		List<PermissionSetGroup> groups = [
			SELECT Id, DeveloperName, MasterLabel, Description, Status
			FROM PermissionSetGroup
			WHERE DeveloperName = :developerName
			WITH SYSTEM_MODE
			LIMIT 1
		];
		return groups.isEmpty() ? null : groups[0];
	}

	/**
	 * Returns a single permission set group by DeveloperName.
	 *
	 * @param developerName the DeveloperName to look for
	 * @return the group, or null when the org does not have it
	 */
	public PermissionSetGroup selectByDeveloperName(String developerName) {
		if (String.isBlank(developerName)) {
			return null;
		}
		List<PermissionSetGroup> groups = selectByDeveloperNames(new Set<String>{ developerName });
		return groups.isEmpty() ? null : groups[0];
	}
}
