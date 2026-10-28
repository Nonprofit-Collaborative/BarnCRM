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
        public Boolean canChangeAccess;
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
     * roles, the five roles, and who holds each one. Only for someone with Manage BarnCRM
     * Settings, like the user search: who holds which role and permission is not for every
     * BarnCRM user to read. Anyone else gets empty lists and a refusal the page shows.
     *
     * @return the roles and their members, or a structured error
     */
    @AuraEnabled(cacheable=true)
    public static AccessResult getAccessOverview() {
        AccessResult result = new AccessResult();
        if (!result.canManage) {
            result.roles = new List<AccessService.Role>();
            result.assignments = new List<AccessService.RoleAssignments>();
            result.addOns = new List<AccessService.AddOn>();
            result.addOnAssignments = new List<AccessService.AddOnAssignments>();
            result.canChangeAccess = false;
            result.success = false;
            result.errorCode = ERROR_NO_PERMISSION;
            result.message = Label.Core_Access_ErrorRolesNotVisible;
            return result;
        }
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
        // Giving a role or an add-on needs both Manage BarnCRM Settings and what Setup itself
        // would need, so the page can disable both up front (ADR-0121).
        result.canChangeAccess = AccessService.changeRefusal() == null;
        // Extra permissions are loaded on their own, so a failure here never hides the roles.
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
     * Shared path for giving and taking away an add-on: the permission refusal the service
     * would give (so the page gets a code it can branch on), input validation, then the
     * service call, which enforces both permission checks itself.
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
        String refusal = AccessService.changeRefusal();
        if (refusal != null) {
            result.success = false;
            result.errorCode = ERROR_NO_PERMISSION;
            result.message = refusal;
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
            Set<Id> people = new Set<Id>{ assigneeId };
            List<String> refusals = isAssign
                ? AccessService.assignAddOn(people, permissionSetName)
                : AccessService.removeAddOn(people, permissionSetName);
            if (!refusals.isEmpty()) {
                // Salesforce refused the person, usually for their license: the message names
                // them and gives Salesforce's reason, and is already in the Error Log.
                throw new AccessService.AccessException(String.join(refusals, ' '));
            }
            TabAccessService.requestSync();
            ModuleAccessSyncs.requestAll();
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
     * Shared path for giving and taking away a role: the same permission check as for
     * add-ons (Manage BarnCRM Settings, and Assign Permission Sets or Manage Users), so a
     * person without the Salesforce permission gets a plain reason rather than the
     * platform's refusal, then input validation, then the service call.
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
        String refusal = AccessService.changeRefusal();
        if (refusal != null) {
            result.success = false;
            result.errorCode = ERROR_NO_PERMISSION;
            result.message = refusal;
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
            // The switchable tabs follow the role (ADR-0124), and so do the modules' own sets
            // (ADR-0131 `0131-module-access-sync-by-role.md`).
            TabAccessService.requestSync();
            ModuleAccessSyncs.requestAll();
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
