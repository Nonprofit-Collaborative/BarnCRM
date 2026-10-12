/**
 * Who holds a custom permission, asked for by name (feature C-11).
 *
 * A module's Health Check asks it who holds a permission the module ships, and has to name
 * the people holding it, because "somebody has it" is not something an administrator can act
 * on. Giving asks it about `Override_Receipt_Lock` (ADR-0024), through
 * `HealthCheckGivingChecks` since C-29 (ADR-0059); Core's Error Log digest asks it too.
 *
 * `CustomPermission`, `SetupEntityAccess`, `PermissionSet` and `PermissionSetAssignment` are
 * platform setup objects present in every Salesforce org, and the permission is matched on
 * `DeveloperName`, which is a String this class is handed, so a permission that is not in the
 * org is simply held by nobody. The name is deliberately not namespace qualified:
 * a packaged custom permission keeps its bare `DeveloperName` and carries the namespace in
 * `NamespacePrefix`, so qualifying it would find nothing once the namespace is registered.
 *
 * All SOQL for the question lives here (plan Section 7.1) and runs in user mode, like every
 * other Health Check query.
 */
@NamespaceAccessible
public with sharing class CustomPermissionSelector {
    /** How many holders a finding names before it counts the rest. */
    public static final Integer NAMES_SHOWN = 3;

    /**
     * The most holders read back. An org that has handed this permission to more people than
     * this has a problem the first three names already describe.
     */
    private static final Integer HOLDER_LIMIT = 200;

    /** Injected by the tests, which cannot create a custom permission with DML. */
    @TestVisible
    private static Holders holdersOverride;

    /**
     * Who holds one custom permission. `readable` is false when the running user is not
     * allowed to see setup entities at all, which is not the same answer as "nobody holds
     * it" and is reported as no finding rather than as a clean bill of health.
     */
    @NamespaceAccessible
    public class Holders {
        @NamespaceAccessible
        public Boolean readable;
        @NamespaceAccessible
        public Integer total;
        @NamespaceAccessible
        public List<String> names;

        @NamespaceAccessible
        public Holders() {
            this.readable = true;
            this.total = 0;
            this.names = new List<String>();
        }
    }

    /**
     * The active users holding the named custom permission, through a permission set, a
     * permission set group, or the profile that owns one.
     */
    @NamespaceAccessible
    public static Holders holders(String developerName) {
        if (holdersOverride != null) {
            return holdersOverride;
        }

        Holders result = new Holders();
        try {
            for (User holder : activeHolders(developerName)) {
                result.total++;
                if (result.names.size() < NAMES_SHOWN) {
                    result.names.add(holder.Name);
                }
            }
        } catch (System.SecurityException cannotSeeSetup) {
            // A user-mode query the viewer may not run throws this rather than QueryException.
            result = unreadable();
        } catch (QueryException cannotSeeSetup) {
            result = unreadable();
        }

        return result;
    }

    /**
     * The Ids of the active users holding the named custom permission, in name order: the
     * people the error digest goes to when nobody has named its recipients (C-23, R-E5). A user
     * who cannot see setup entities gets an empty list, as `holders` reports them unreadable.
     */
    public static List<Id> holderIds(String developerName) {
        List<Id> ids = new List<Id>();
        try {
            for (User holder : activeHolders(developerName)) {
                ids.add(holder.Id);
            }
        } catch (System.SecurityException cannotSeeSetup) {
            ids.clear();
        } catch (QueryException cannotSeeSetup) {
            ids.clear();
        }
        return ids;
    }

    private static Holders unreadable() {
        Holders result = new Holders();
        result.readable = false;
        result.total = 0;
        result.names = new List<String>();
        return result;
    }

    /**
     * The active users holding the named custom permission, through a permission set, a
     * permission set group, or the profile that owns one. Throws QueryException for a reader
     * who cannot see setup entities; each caller decides what that means.
     */
    private static List<User> activeHolders(String developerName) {
        if (String.isBlank(developerName)) {
            return new List<User>();
        }
        Set<Id> permissionIds = customPermissionIds(developerName);
        if (permissionIds.isEmpty()) {
            return new List<User>();
        }

        Set<Id> permissionSetIds = grantingPermissionSetIds(permissionIds);
        if (permissionSetIds.isEmpty()) {
            return new List<User>();
        }

        Set<Id> profileIds = owningProfileIds(permissionSetIds);
        Set<Id> assignedUserIds = assigneeIds(permissionSetIds);
        if (profileIds.isEmpty() && assignedUserIds.isEmpty()) {
            return new List<User>();
        }

        return [
            SELECT Id, Name
            FROM User
            WHERE IsActive = TRUE AND (Id IN :assignedUserIds OR ProfileId IN :profileIds)
            WITH USER_MODE
            ORDER BY Name
            LIMIT :HOLDER_LIMIT
        ];
    }

    /** The named custom permission, or nothing at all in an org without the package. */
    private static Set<Id> customPermissionIds(String developerName) {
        Set<Id> permissionIds = new Set<Id>();
        for (CustomPermission permission : [
            SELECT Id
            FROM CustomPermission
            WHERE DeveloperName = :developerName
            WITH USER_MODE
        ]) {
            permissionIds.add(permission.Id);
        }
        return permissionIds;
    }

    /**
     * The permission sets that grant the permission. A permission set group grants it through
     * its own aggregate permission set, which is what an assignment made from a group points
     * at, so both routes are covered by the assignment query below.
     */
    private static Set<Id> grantingPermissionSetIds(Set<Id> permissionIds) {
        Set<Id> permissionSetIds = new Set<Id>();
        for (SetupEntityAccess access : [
            SELECT ParentId
            FROM SetupEntityAccess
            WHERE SetupEntityId IN :permissionIds
            WITH USER_MODE
        ]) {
            permissionSetIds.add(access.ParentId);
        }
        return permissionSetIds;
    }

    /**
     * The profiles that grant it. A permission granted on a profile has no assignment row of
     * its own: everyone on that profile holds it, which is the widest way to leave this
     * permission lying around and the one worth reporting most.
     */
    private static Set<Id> owningProfileIds(Set<Id> permissionSetIds) {
        Set<Id> profileIds = new Set<Id>();
        for (PermissionSet owner : [
            SELECT ProfileId
            FROM PermissionSet
            WHERE Id IN :permissionSetIds AND IsOwnedByProfile = TRUE
            WITH USER_MODE
        ]) {
            if (owner.ProfileId != null) {
                profileIds.add(owner.ProfileId);
            }
        }
        return profileIds;
    }

    /** The people assigned one of the granting permission sets. */
    private static Set<Id> assigneeIds(Set<Id> permissionSetIds) {
        Set<Id> assignees = new Set<Id>();
        for (PermissionSetAssignment assignment : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSetId IN :permissionSetIds
            WITH USER_MODE
        ]) {
            assignees.add(assignment.AssigneeId);
        }
        return assignees;
    }
}
