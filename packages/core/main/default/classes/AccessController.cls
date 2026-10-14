/**
 * The Access page's connection to Apex.
 *
 * Every method validates what it was given, checks the Manage BarnCRM Settings custom
 * permission before changing anything, and returns an AccessResult rather than throwing,
 * so the component always has a message it can put in front of a person.
 */
public with sharing class AccessController {
    /** Error codes the component can branch on without reading the message text. */
    public static final String ERROR_NO_PERMISSION = 'NO_PERMISSION';
    public static final String ERROR_INVALID_INPUT = 'INVALID_INPUT';
    public static final String ERROR_FAILED = 'FAILED';

    /** What every method on this controller returns. Unused fields stay null. */
    public class AccessResult {
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String errorCode;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public List<AccessService.Role> roles;
        @AuraEnabled
        public List<AccessService.RoleAssignments> assignments;
        @AuraEnabled
        public List<AccessService.UserSummary> users;
        @AuraEnabled
        public Id currentUserId;
        @AuraEnabled
        public Boolean canAssignAddOns;
        @AuraEnabled
        public List<AccessService.AddOn> addOns;
        @AuraEnabled
        public List<AccessService.AddOnAssignments> addOnAssignments;

        /**
         * Starts a successful result that already knows who is looking at the page and
         * whether they may change anything on it.
         */
        public AccessResult() {
            this.success = true;
            this.canManage = canManageAccess();
            this.currentUserId = UserInfo.getUserId();
        }
    }

    /**
     * Returns everything the page needs to draw itself: whether this person may change
     * roles, the five roles, and who holds each one.
     *
     * @return the roles and their members, or a structured error
     */
    @AuraEnabled(cacheable=true)
    public static AccessResult getAccessOverview() {
        AccessResult result = new AccessResult();
        try {
            result.roles = AccessService.getRoles();
            result.assignments = AccessService.getAssignments();
        } catch (AccessService.AccessException e) {
            // Never leave the page blank without saying why. A person who may not change
            // roles can also be a person whose org does not let them read the roles at
            // all, and an empty page with no explanation is the worst of both.
            result.roles = new List<AccessService.Role>();
            result.assignments = new List<AccessService.RoleAssignments>();
            result.success = false;
            result.errorCode = ERROR_FAILED;
            result.message = result.canManage
                ? e.getMessage()
                : Label.Core_Access_ErrorRolesNotVisible;
        }
        // Extra permissions are loaded on their own, so a failure here never hides the roles.
        // Giving one needs both Manage BarnCRM Settings and what Setup itself would need.
        result.canAssignAddOns = result.canManage && AccessService.canAssignPermissionSets();
        try {
            result.addOns = AccessService.getAddOns();
            result.addOnAssignments = AccessService.getAddOnAssignments();
        } catch (AccessService.AccessException e) {
            result.addOns = new List<AccessService.AddOn>();
            result.addOnAssignments = new List<AccessService.AddOnAssignments>();
        }
        return result;
    }

    /**
     * Gives one person one of the Core add-on permission sets.
     *
     * @param userId the person, as an Id in text form
     * @param permissionSetName the API name of one of the Core add-on permission sets
     * @return success, or a structured error the page can show
     */
    @AuraEnabled
    public static AccessResult assignAddOn(String userId, String permissionSetName) {
        return changeAddOn(userId, permissionSetName, true);
    }

    /**
     * Takes one of the Core add-on permission sets away from one person.
     *
     * @param userId the person, as an Id in text form
     * @param permissionSetName the API name of one of the Core add-on permission sets
     * @return success, or a structured error the page can show
     */
    @AuraEnabled
    public static AccessResult removeAddOn(String userId, String permissionSetName) {
        return changeAddOn(userId, permissionSetName, false);
    }

    /**
     * Shared path for giving and taking away an add-on: both permission checks, input
     * validation, then the service call, which checks the Setup permission again.
     *
     * @param userId the person, as an Id in text form
     * @param permissionSetName the API name of one of the Core add-on permission sets
     * @param isAssign true to give the add-on, false to take it away
     * @return success, or a structured error the page can show
     */
    private static AccessResult changeAddOn(
        String userId,
        String permissionSetName,
        Boolean isAssign
    ) {
        AccessResult result = new AccessResult();
        if (!result.canManage) {
            result.success = false;
            result.errorCode = ERROR_NO_PERMISSION;
            result.message = Label.Core_Access_ErrorNoPermission;
            return result;
        }
        if (!AccessService.canAssignPermissionSets()) {
            result.success = false;
            result.errorCode = ERROR_NO_PERMISSION;
            result.message = Label.Core_Access_ErrorCannotAssignPermissionSets;
            return result;
        }
        Id assigneeId = toUserId(userId);
        if (assigneeId == null || String.isBlank(permissionSetName)) {
            result.success = false;
            result.errorCode = ERROR_INVALID_INPUT;
            result.message = Label.Core_Access_ErrorInvalidInput;
            return result;
        }
        try {
            if (isAssign) {
                List<String> failures = AccessService.assignAddOn(
                    new Set<Id>{ assigneeId },
                    permissionSetName
                );
                if (!failures.isEmpty()) {
                    result.success = false;
                    result.errorCode = ERROR_FAILED;
                    result.message = String.join(failures, ' ');
                }
            } else {
                AccessService.removeAddOn(new Set<Id>{ assigneeId }, permissionSetName);
            }
        } catch (AccessService.AccessException e) {
            result.success = false;
            result.errorCode = ERROR_FAILED;
            result.message = e.getMessage();
        }
        return result;
    }

    /**
     * Finds active people whose name or email address starts with the term.
     *
     * @param term what the admin typed
     * @return at most twenty people, or a structured error
     */
    @AuraEnabled(cacheable=true)
    public static AccessResult searchUsers(String term) {
        AccessResult result = new AccessResult();
        result.users = new List<AccessService.UserSummary>();
        if (String.isBlank(term)) {
            return result;
        }
        if (!result.canManage) {
            // Only someone who may give roles needs to look people up by name and email.
            result.success = false;
            result.errorCode = ERROR_NO_PERMISSION;
            result.message = Label.Core_Access_ErrorNoPermission;
            return result;
        }
        try {
            result.users = AccessService.searchUsers(term);
        } catch (AccessService.AccessException e) {
            result.success = false;
            result.errorCode = ERROR_FAILED;
            result.message = e.getMessage();
        }
        return result;
    }

    /**
     * Gives one person one role.
     *
     * @param userId the person, as an Id in text form
     * @param roleDeveloperName the DeveloperName of one of the five packaged roles
     * @return success, or a structured error the page can show
     */
    @AuraEnabled
    public static AccessResult assignRole(String userId, String roleDeveloperName) {
        return changeRole(userId, roleDeveloperName, true);
    }

    /**
     * Takes one role away from one person.
     *
     * @param userId the person, as an Id in text form
     * @param roleDeveloperName the DeveloperName of one of the five packaged roles
     * @return success, or a structured error the page can show
     */
    @AuraEnabled
    public static AccessResult removeRole(String userId, String roleDeveloperName) {
        return changeRole(userId, roleDeveloperName, false);
    }

    /**
     * Shared path for giving and taking away a role: permission check, input validation,
     * then the service call.
     *
     * @param userId the person, as an Id in text form
     * @param roleDeveloperName the DeveloperName of one of the five packaged roles
     * @param isAssign true to give the role, false to take it away
     * @return success, or a structured error the page can show
     */
    private static AccessResult changeRole(
        String userId,
        String roleDeveloperName,
        Boolean isAssign
    ) {
        AccessResult result = new AccessResult();
        if (!result.canManage) {
            result.success = false;
            result.errorCode = ERROR_NO_PERMISSION;
            result.message = Label.Core_Access_ErrorNoPermission;
            return result;
        }
        Id assigneeId = toUserId(userId);
        if (assigneeId == null || String.isBlank(roleDeveloperName)) {
            result.success = false;
            result.errorCode = ERROR_INVALID_INPUT;
            result.message = Label.Core_Access_ErrorInvalidInput;
            return result;
        }
        try {
            if (isAssign) {
                AccessService.assignRole(assigneeId, roleDeveloperName);
            } else {
                AccessService.removeRole(assigneeId, roleDeveloperName);
            }
        } catch (AccessService.AccessException e) {
            result.success = false;
            result.errorCode = ERROR_FAILED;
            result.message = e.getMessage();
        }
        return result;
    }

    /**
     * Turns the text the page sent into a User Id, or null when it is not one.
     *
     * @param userId the value to convert
     * @return the Id, or null when the value is blank or is not a User Id
     */
    private static Id toUserId(String userId) {
        if (String.isBlank(userId)) {
            return null;
        }
        try {
            Id candidate = Id.valueOf(userId.trim());
            return candidate.getSobjectType() == Schema.User.SObjectType ? candidate : null;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Whether the person using the page may change roles.
     *
     * @return true when they hold the Manage BarnCRM Settings custom permission
     */
    private static Boolean canManageAccess() {
        return BarnCRMPermissions.canManageSettings();
    }
}
