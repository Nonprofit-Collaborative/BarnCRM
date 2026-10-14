/**
 * Reads users for the Access page: the search box, and the people already in a role.
 */
public with sharing class UserSelector {
    private static final String GUEST_USER_TYPE = 'Guest';

    /**
     * Finds active, non guest users whose name or email address starts with the term.
     *
     * @param term what the admin typed; blank returns no results
     * @param maxResults the largest number of users to return
     * @return the matching users, ordered by name
     */
    public List<User> searchActive(String term, Integer maxResults) {
        if (String.isBlank(term) || maxResults == null || maxResults <= 0) {
            return new List<User>();
        }
        String pattern = escapeForLike(term.trim()) + '%';
        Integer resultLimit = maxResults;
        return [
            SELECT Id, Name, Email, Username, IsActive
            FROM User
            WHERE
                IsActive = TRUE
                AND UserType != :GUEST_USER_TYPE
                AND (Name LIKE :pattern
                OR Email LIKE :pattern)
            WITH USER_MODE
            ORDER BY Name
            LIMIT :resultLimit
        ];
    }

    /**
     * Returns active, non guest users by Id. Used to check that a chosen person is real
     * and still able to sign in before a role is given to them.
     *
     * @param userIds the user Ids to load
     * @return the matching active users
     */
    public List<User> selectActiveByIds(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new List<User>();
        }
        return [
            SELECT Id, Name, Email, IsActive
            FROM User
            WHERE Id IN :userIds AND IsActive = TRUE AND UserType != :GUEST_USER_TYPE
            WITH USER_MODE
            ORDER BY Name
        ];
    }

    /**
     * Returns the running user's effective Assign Permission Sets and Manage Users
     * permissions: everything their profile, permission sets and permission set groups give,
     * after muting, as Salesforce itself evaluates it.
     *
     * @return the running user's permission access, or null when none is returned
     */
    public UserPermissionAccess selectRunningUserPermissionAccess() {
        List<UserPermissionAccess> access = [
            SELECT PermissionsAssignPermissionSets, PermissionsManageUsers
            FROM UserPermissionAccess
            WITH USER_MODE
            LIMIT 1
        ];
        return access.isEmpty() ? null : access[0];
    }

    /**
     * Escapes the characters that carry meaning inside a SOQL LIKE pattern, so that a
     * person searching for "a_b" is not offered every three letter name.
     *
     * @param term the raw search term
     * @return the term with backslash, percent, and underscore escaped
     */
    private String escapeForLike(String term) {
        return term.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }
}
