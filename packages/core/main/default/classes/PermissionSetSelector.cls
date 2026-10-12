/**
 * Reads the packaged permission sets themselves, as opposed to the groups that carry them.
 *
 * A permission set has no calculation status: unlike a permission set group it can be
 * assigned the moment the package finishes installing. That is why the post-install script
 * uses one as its guaranteed step.
 */
public with sharing class PermissionSetSelector {
    /**
     * Returns one permission set by its API name, in system mode.
     *
     * Used only by the post-install script, which runs as a platform user with no session
     * and no permission set of its own, so user mode has nothing to enforce against.
     *
     * @param permissionSetName the permission set's API name, for example BarnCRM_Admin
     * @return the permission set, or null when the org does not have it
     */
    public PermissionSet selectByNameInSystemMode(String permissionSetName) {
        if (String.isBlank(permissionSetName)) {
            return null;
        }
        List<PermissionSet> sets = [
            SELECT Id, Name, Label
            FROM PermissionSet
            WHERE Name = :permissionSetName AND IsOwnedByProfile = FALSE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return sets.isEmpty() ? null : sets[0];
    }
}
