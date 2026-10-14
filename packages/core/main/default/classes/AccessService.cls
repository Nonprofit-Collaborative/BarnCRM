/**
 * The business logic behind the Access page: the five packaged roles, who holds them,
 * and giving or taking a role away.
 *
 * A role is a packaged permission set group. Nothing here refers to a group by Id, only
 * by DeveloperName, so the same code works in every org.
 *
 * Every failure is written to the Error Log and rethrown as an AccessException carrying
 * a message from a Custom Label, so the component always has something it can show to a
 * person rather than a platform stack trace.
 */
public with sharing class AccessService {
    /** The DeveloperName of the group that grants BarnCRM Settings. */
    public static final String ADMIN_ROLE = 'BarnCRM_Admin_Group';

    /** The permission set inside that group, assignable before the group is calculated. */
    public static final String ADMIN_PERMISSION_SET = 'BarnCRM_Admin';

    /** The five packaged roles, in the order the page shows them. */
    public static final List<String> ROLE_DEVELOPER_NAMES = new List<String>{
        ADMIN_ROLE,
        'Fundraising_Staff',
        'Program_Staff',
        'Volunteer_Coordinator',
        'Read_Only'
    };

    /**
     * The add-on permission sets the Access page may give and take away, in the order the
     * page shows them. These are the packaged Core permission sets that no role includes (or,
     * for Find and Export, that only BarnCRM Admin includes), and nothing else: the page never
     * assigns an arbitrary permission set. Each is resolved by API name in the package's own
     * namespace at runtime, never by Id.
     *
     * Module permission sets (Giving Staff and the rest) are out of scope. Core has no
     * extension point through which a module contributes roles or permission sets to this
     * page today; when one is added, its sets join this list through it rather than by name.
     */
    public static final List<String> ADD_ON_PERMISSION_SETS = new List<String>{
        'BarnCRM_Find_And_Export',
        'BarnCRM_Bulk_Update',
        'BarnCRM_Bulk_Delete',
        'BarnCRM_Erase_People',
        'BarnCRM_Duplicate_Review',
        'BarnCRM_Metadata_Admin'
    };

    /** The add-ons that let a person remove data, which the page warns about. */
    public static final Set<String> DESTRUCTIVE_ADD_ONS = new Set<String>{
        'BarnCRM_Bulk_Delete',
        'BarnCRM_Erase_People'
    };

    /**
     * Stands in for the Assign Permission Sets check in tests. No packaged permission set
     * carries Manage BarnCRM Settings without Assign Permission Sets, but an org's own can,
     * so the refusal for that person is proven by setting this to false.
     */
    @TestVisible
    private static Boolean assignPermissionSetsOverride;

    private static final String READY_STATUS = 'Updated';
    private static final Integer USER_SEARCH_LIMIT = 20;

    private static PermissionSetGroupSelector groupSelector = new PermissionSetGroupSelector();
    private static PermissionSetAssignmentSelector assignmentSelector = new PermissionSetAssignmentSelector();
    private static UserSelector userSelector = new UserSelector();
    private static PermissionSetSelector permissionSetSelector = new PermissionSetSelector();

    /** Thrown for every failure the Access page can meet, with a message fit to display. */
    public class AccessException extends Exception {
    }

    /** One of the five packaged roles, as the page shows it. */
    public class Role {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Boolean isReady;

        /**
         * Describes one role from the permission set group that carries it.
         *
         * @param groupRecord the packaged permission set group
         */
        public Role(PermissionSetGroup groupRecord) {
            this.developerName = groupRecord.DeveloperName;
            this.label = groupRecord.MasterLabel;
            this.description = groupRecord.Description;
            this.isReady = READY_STATUS.equalsIgnoreCase(groupRecord.Status);
        }
    }

    /** A person, named the way the page names them. */
    public class UserSummary {
        @AuraEnabled
        public Id userId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String email;

        /**
         * Describes one person for the page.
         *
         * @param userId the person's Id
         * @param name the person's name
         * @param email the person's email address, shown so two people with one name can be told apart
         */
        public UserSummary(Id userId, String name, String email) {
            this.userId = userId;
            this.name = name;
            this.email = email;
        }
    }

    /** The people who hold one role. */
    public class RoleAssignments {
        @AuraEnabled
        public String roleDeveloperName;
        @AuraEnabled
        public List<UserSummary> users;

        /**
         * Starts an empty list of the people who hold one role.
         *
         * @param roleDeveloperName the role's DeveloperName
         */
        public RoleAssignments(String roleDeveloperName) {
            this.roleDeveloperName = roleDeveloperName;
            this.users = new List<UserSummary>();
        }
    }

    /** One add-on permission set, as the page shows it. */
    public class AddOn {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Boolean isDestructive;
        @AuraEnabled
        public String warning;

        /**
         * Describes one add-on from the packaged permission set that carries it.
         *
         * @param permissionSetRecord the packaged permission set
         */
        public AddOn(PermissionSet permissionSetRecord) {
            this.developerName = permissionSetRecord.Name;
            this.label = permissionSetRecord.Label;
            this.description = addOnDescription(permissionSetRecord.Name);
            this.isDestructive = DESTRUCTIVE_ADD_ONS.contains(permissionSetRecord.Name);
            // System.Label: a bare Label here would resolve to this class's own label field.
            this.warning = this.isDestructive
                ? System.Label.Core_Access_AddOnDestructiveWarning
                : null;
        }
    }

    /** The people who hold one add-on directly. */
    public class AddOnAssignments {
        @AuraEnabled
        public String permissionSetName;
        @AuraEnabled
        public List<UserSummary> users;

        /**
         * Starts an empty list of the people who hold one add-on.
         *
         * @param permissionSetName the add-on's API name
         */
        public AddOnAssignments(String permissionSetName) {
            this.permissionSetName = permissionSetName;
            this.users = new List<UserSummary>();
        }
    }

    /**
     * Returns the add-on permission sets this org has, with a one sentence description of
     * what each grants.
     *
     * @return the add-ons, in the page's order
     */
    public static List<AddOn> getAddOns() {
        Map<String, PermissionSet> setsByName = loadAddOnSets();
        List<AddOn> addOns = new List<AddOn>();
        for (String name : ADD_ON_PERMISSION_SETS) {
            PermissionSet permissionSetRecord = setsByName.get(name);
            if (permissionSetRecord != null) {
                addOns.add(new AddOn(permissionSetRecord));
            }
        }
        return addOns;
    }

    /**
     * Returns the people who hold each add-on directly, one entry per add-on this org has.
     * Holding an add-on only through a role (BarnCRM Admin includes Find and Export) is not
     * listed, because removing it here could not take it away.
     *
     * @return the assignments, in the same order as getAddOns
     */
    public static List<AddOnAssignments> getAddOnAssignments() {
        Map<String, PermissionSet> setsByName = loadAddOnSets();
        Map<Id, AddOnAssignments> resultsById = new Map<Id, AddOnAssignments>();
        List<AddOnAssignments> results = new List<AddOnAssignments>();
        for (String name : ADD_ON_PERMISSION_SETS) {
            PermissionSet permissionSetRecord = setsByName.get(name);
            if (permissionSetRecord != null) {
                AddOnAssignments entry = new AddOnAssignments(name);
                resultsById.put(permissionSetRecord.Id, entry);
                results.add(entry);
            }
        }
        if (resultsById.isEmpty()) {
            return results;
        }
        try {
            for (
                PermissionSetAssignment assignment : assignmentSelector.selectByPermissionSetIds(
                    resultsById.keySet()
                )
            ) {
                resultsById.get(assignment.PermissionSetId)
                    .users.add(
                        new UserSummary(
                            assignment.AssigneeId,
                            assignment.Assignee.Name,
                            assignment.Assignee.Email
                        )
                    );
            }
        } catch (Exception e) {
            throw logAndWrap(
                e,
                'AccessService.getAddOnAssignments',
                Label.Core_Access_ErrorUnexpected
            );
        }
        return results;
    }

    /**
     * Whether the running user could assign permission sets in Setup: they hold Assign
     * Permission Sets or Manage Users through their profile, a permission set, or a role.
     * Any failure to tell counts as no.
     *
     * @return true when they hold either permission
     */
    public static Boolean canAssignPermissionSets() {
        if (assignPermissionSetsOverride != null) {
            return assignPermissionSetsOverride;
        }
        try {
            return assignmentSelector.countAssignPermissionSetsGrants(UserInfo.getUserId()) > 0;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Gives a set of people one add-on permission set. People who already hold it directly
     * are skipped. Each person is inserted on their own terms: when Salesforce refuses one
     * person, usually because their license does not allow what the add-on grants, the
     * others still get it, and that person is reported by name.
     *
     * @param userIds the people to give the add-on to
     * @param permissionSetName the API name of one of the Core add-on permission sets
     * @return one plain message per person who could not be given it; empty when all were
     */
    public static List<String> assignAddOn(Set<Id> userIds, String permissionSetName) {
        requireAssignPermission();
        PermissionSet permissionSetRecord = requireAddOn(permissionSetName);
        Map<Id, User> targets = requireActiveUserMap(userIds);

        Set<Id> alreadyAssigned = new Set<Id>();
        List<PermissionSetAssignment> rows = new List<PermissionSetAssignment>();
        try {
            for (
                PermissionSetAssignment assignment : assignmentSelector.selectByPermissionSetIdAndUserIds(
                    permissionSetRecord.Id,
                    targets.keySet()
                )
            ) {
                alreadyAssigned.add(assignment.AssigneeId);
            }
            for (Id userId : targets.keySet()) {
                if (!alreadyAssigned.contains(userId)) {
                    rows.add(
                        new PermissionSetAssignment(
                            AssigneeId = userId,
                            PermissionSetId = permissionSetRecord.Id
                        )
                    );
                }
            }
            if (rows.isEmpty()) {
                return new List<String>();
            }
            List<String> failures = describeFailures(
                rows,
                Database.insert(rows, false, AccessLevel.USER_MODE),
                targets,
                permissionSetRecord.Label
            );
            if (!failures.isEmpty()) {
                ErrorLogger.logMessages(
                    failures,
                    'AccessService.assignAddOn',
                    ErrorLogger.SEVERITY_ERROR
                );
            }
            return failures;
        } catch (Exception e) {
            throw logAndWrap(e, 'AccessService.assignAddOn', Label.Core_Access_ErrorUnexpected);
        }
    }

    /**
     * Takes one add-on permission set away from a set of people, in a single DML operation.
     * Removing an add-on a person does not hold directly changes nothing and is not an error.
     *
     * @param userIds the people to take the add-on from
     * @param permissionSetName the API name of one of the Core add-on permission sets
     */
    public static void removeAddOn(Set<Id> userIds, String permissionSetName) {
        requireAssignPermission();
        PermissionSet permissionSetRecord = requireAddOn(permissionSetName);
        Set<Id> targets = requireChosenPeople(userIds);
        try {
            List<PermissionSetAssignment> toDelete = assignmentSelector.selectByPermissionSetIdAndUserIds(
                permissionSetRecord.Id,
                targets
            );
            if (!toDelete.isEmpty()) {
                Database.delete(toDelete, true, AccessLevel.USER_MODE);
            }
        } catch (Exception e) {
            throw logAndWrap(e, 'AccessService.removeAddOn', Label.Core_Access_ErrorUnexpected);
        }
    }

    /**
     * Turns the per-row results of an insert into one plain message per person refused.
     * Kept separate from the DML so that the refusal path, which in a real org is a license
     * that does not allow what the add-on grants, can be proven without such a user.
     *
     * @param rows the assignment rows, in the order they were inserted
     * @param results the insert results, one per row in the same order
     * @param people the people, by Id, to name in the messages
     * @param addOnLabel the add-on's label
     * @return one message per refused row; empty when every row was saved
     */
    @TestVisible
    private static List<String> describeFailures(
        List<PermissionSetAssignment> rows,
        List<Database.SaveResult> results,
        Map<Id, User> people,
        String addOnLabel
    ) {
        List<String> failures = new List<String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                continue;
            }
            List<String> reasons = new List<String>();
            for (Database.Error error : results[i].getErrors()) {
                reasons.add(error.getMessage());
            }
            User person = people == null ? null : people.get(rows[i].AssigneeId);
            failures.add(
                String.format(
                    Label.Core_Access_ErrorAddOnRefused,
                    new List<Object>{
                        person == null ? String.valueOf(rows[i].AssigneeId) : person.Name,
                        addOnLabel,
                        String.join(reasons, ' ')
                    }
                )
            );
        }
        return failures;
    }

    /**
     * The one plain sentence the page shows for what an add-on grants.
     *
     * @param permissionSetName the add-on's API name
     * @return the sentence, or null for a name that is not an add-on
     */
    private static String addOnDescription(String permissionSetName) {
        switch on permissionSetName {
            when 'BarnCRM_Find_And_Export' {
                return Label.Core_Access_AddOnFindAndExport;
            }
            when 'BarnCRM_Bulk_Update' {
                return Label.Core_Access_AddOnBulkUpdate;
            }
            when 'BarnCRM_Bulk_Delete' {
                return Label.Core_Access_AddOnBulkDelete;
            }
            when 'BarnCRM_Erase_People' {
                return Label.Core_Access_AddOnErasePeople;
            }
            when 'BarnCRM_Duplicate_Review' {
                return Label.Core_Access_AddOnDuplicateReview;
            }
            when 'BarnCRM_Metadata_Admin' {
                return Label.Core_Access_AddOnMetadataAdmin;
            }
            when else {
                return null;
            }
        }
    }

    /**
     * Loads the packaged add-on permission sets, keyed by API name. Only sets in this
     * package's own namespace count, so a same-named set an admin created is never used.
     *
     * @return the add-ons this org has
     */
    private static Map<String, PermissionSet> loadAddOnSets() {
        Map<String, PermissionSet> setsByName = new Map<String, PermissionSet>();
        try {
            for (
                PermissionSet permissionSetRecord : permissionSetSelector.selectPackagedByNames(
                    new Set<String>(ADD_ON_PERMISSION_SETS),
                    NamespaceUtil.prefix().removeEnd('__')
                )
            ) {
                setsByName.put(permissionSetRecord.Name, permissionSetRecord);
            }
        } catch (Exception e) {
            throw logAndWrap(e, 'AccessService.loadAddOnSets', Label.Core_Access_ErrorUnexpected);
        }
        return setsByName;
    }

    /** Refuses, with a readable message, a person who could not assign permission sets in Setup. */
    private static void requireAssignPermission() {
        if (!canAssignPermissionSets()) {
            throw new AccessException(Label.Core_Access_ErrorCannotAssignPermissionSets);
        }
    }

    /**
     * Checks that the name is on the add-on allowlist and that the org has that packaged set.
     *
     * @param permissionSetName the API name to check
     * @return the packaged permission set
     */
    private static PermissionSet requireAddOn(String permissionSetName) {
        if (
            String.isBlank(permissionSetName) ||
            !new Set<String>(ADD_ON_PERMISSION_SETS).contains(permissionSetName)
        ) {
            throw new AccessException(Label.Core_Access_ErrorAddOnNotFound);
        }
        PermissionSet permissionSetRecord = loadAddOnSets().get(permissionSetName);
        if (permissionSetRecord == null) {
            throw new AccessException(Label.Core_Access_ErrorAddOnNotFound);
        }
        return permissionSetRecord;
    }

    /**
     * Returns the five packaged roles with their labels and plain language descriptions.
     *
     * @return the roles that exist in this org, in the page's order
     */
    public static List<Role> getRoles() {
        Map<String, PermissionSetGroup> groupsByName = loadRoleGroups();
        List<Role> roles = new List<Role>();
        for (String developerName : ROLE_DEVELOPER_NAMES) {
            PermissionSetGroup groupRecord = groupsByName.get(developerName);
            if (groupRecord != null) {
                roles.add(new Role(groupRecord));
            }
        }
        return roles;
    }

    /**
     * Returns the people who hold each role, one entry per role that exists in this org.
     *
     * @return the assignments, in the same order as getRoles
     */
    public static List<RoleAssignments> getAssignments() {
        Map<String, PermissionSetGroup> groupsByName = loadRoleGroups();
        Map<Id, String> nameByGroupId = new Map<Id, String>();
        Map<String, RoleAssignments> resultsByName = new Map<String, RoleAssignments>();
        List<RoleAssignments> results = new List<RoleAssignments>();
        for (String developerName : ROLE_DEVELOPER_NAMES) {
            PermissionSetGroup groupRecord = groupsByName.get(developerName);
            if (groupRecord == null) {
                continue;
            }
            nameByGroupId.put(groupRecord.Id, developerName);
            RoleAssignments entry = new RoleAssignments(developerName);
            resultsByName.put(developerName, entry);
            results.add(entry);
        }
        if (nameByGroupId.isEmpty()) {
            return results;
        }
        try {
            for (
                PermissionSetAssignment assignment : assignmentSelector.selectByGroupIds(
                    nameByGroupId.keySet()
                )
            ) {
                RoleAssignments entry = resultsByName.get(
                    nameByGroupId.get(assignment.PermissionSetGroupId)
                );
                if (entry != null) {
                    entry.users.add(
                        new UserSummary(
                            assignment.AssigneeId,
                            assignment.Assignee.Name,
                            assignment.Assignee.Email
                        )
                    );
                }
            }
        } catch (Exception e) {
            throw logAndWrap(e, 'AccessService.getAssignments', Label.Core_Access_ErrorUnexpected);
        }
        return results;
    }

    /**
     * Finds active, non guest people whose name or email address starts with the term.
     *
     * @param term what the admin typed
     * @return at most twenty matching people; an empty list for a blank term
     */
    public static List<UserSummary> searchUsers(String term) {
        if (String.isBlank(term)) {
            return new List<UserSummary>();
        }
        try {
            List<UserSummary> summaries = new List<UserSummary>();
            for (User person : userSelector.searchActive(term, USER_SEARCH_LIMIT)) {
                summaries.add(new UserSummary(person.Id, person.Name, person.Email));
            }
            return summaries;
        } catch (Exception e) {
            throw logAndWrap(e, 'AccessService.searchUsers', Label.Core_Access_ErrorUnexpected);
        }
    }

    /**
     * Gives one person one role. Giving a role the person already has changes nothing and
     * is not an error.
     *
     * @param userId the person to give the role to
     * @param roleDeveloperName the DeveloperName of one of the five packaged roles
     */
    public static void assignRole(Id userId, String roleDeveloperName) {
        assignRole(new Set<Id>{ userId }, roleDeveloperName);
    }

    /**
     * Gives a set of people one role, in a single DML operation. People who already hold
     * the role are skipped.
     *
     * @param userIds the people to give the role to
     * @param roleDeveloperName the DeveloperName of one of the five packaged roles
     */
    public static void assignRole(Set<Id> userIds, String roleDeveloperName) {
        PermissionSetGroup groupRecord = requireReadyRole(roleDeveloperName);
        Set<Id> targets = requireActiveUsers(userIds);

        Set<Id> alreadyAssigned = new Set<Id>();
        for (
            PermissionSetAssignment assignment : assignmentSelector.selectByGroupIdsAndUserIds(
                new Set<Id>{ groupRecord.Id },
                targets
            )
        ) {
            alreadyAssigned.add(assignment.AssigneeId);
        }

        List<PermissionSetAssignment> toInsert = buildAssignments(
            targets,
            alreadyAssigned,
            groupRecord.Id
        );
        if (toInsert.isEmpty()) {
            return;
        }
        try {
            Database.insert(toInsert, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw logAndWrap(e, 'AccessService.assignRole', Label.Core_Access_ErrorUnexpected);
        }
    }

    /**
     * Builds the assignment rows one DML statement will insert, skipping the people who
     * already hold the role. Kept separate from the DML so that the collection handling
     * can be proven at any size without spending a user license per record.
     *
     * @param userIds the people to give the role to
     * @param alreadyAssigned the people who already hold it
     * @param groupId the permission set group behind the role
     * @return the rows to insert, one per person who does not yet hold the role
     */
    @TestVisible
    private static List<PermissionSetAssignment> buildAssignments(
        Set<Id> userIds,
        Set<Id> alreadyAssigned,
        Id groupId
    ) {
        List<PermissionSetAssignment> rows = new List<PermissionSetAssignment>();
        for (Id userId : userIds) {
            if (alreadyAssigned == null || !alreadyAssigned.contains(userId)) {
                rows.add(
                    new PermissionSetAssignment(AssigneeId = userId, PermissionSetGroupId = groupId)
                );
            }
        }
        return rows;
    }

    /**
     * Gives one person one packaged permission set during a package install or upgrade.
     *
     * This is the guaranteed half of the bootstrap. A permission set, unlike a permission
     * set group, has no calculation status, so it can be assigned the moment the install
     * finishes and the installing person can open BarnCRM Settings straight away.
     *
     * Documented exception to the user mode rule (plan Section 7.2), and the same one that
     * applies to every method here whose name ends in DuringInstall. A post-install script
     * runs as a platform user: no session, no profile of its own, nothing for user mode to
     * enforce against, so the query and the insert run in system mode. The scope is
     * deliberately one row: the installing person, one packaged permission set, only when
     * they do not already hold it. Nothing here reads user input.
     *
     * These methods are public rather than private only because CorePostInstall and
     * CorePostInstallRetryQueueable are separate classes. They carry no annotation, so
     * ADR-0017 keeps them inside this package, and nothing outside those two callers
     * should use them.
     *
     * @param userId the person who installed or upgraded the package
     * @param permissionSetName the API name of a packaged permission set
     * @return true when the person now holds it, false when the org does not have it
     */
    public static Boolean assignPermissionSetDuringInstall(Id userId, String permissionSetName) {
        if (userId == null || String.isBlank(permissionSetName)) {
            return false;
        }
        PermissionSet permissionSetRecord = permissionSetSelector.selectByNameInSystemMode(
            permissionSetName
        );
        if (permissionSetRecord == null) {
            return false;
        }
        if (
            assignmentSelector.countPermissionSetAssignmentInSystemMode(
                permissionSetRecord.Id,
                userId
            ) > 0
        ) {
            return true;
        }
        Database.insert(
            new List<PermissionSetAssignment>{
                new PermissionSetAssignment(
                    AssigneeId = userId,
                    PermissionSetId = permissionSetRecord.Id
                )
            },
            true,
            AccessLevel.SYSTEM_MODE
        );
        return true;
    }

    /**
     * Tries to give one person one role during a package install or upgrade.
     *
     * A permission set group cannot be assigned while the platform is still calculating
     * it, which is the usual state in the minutes after an install. That is not a failure,
     * it is a "not yet", so this reports it by returning false rather than by throwing:
     * the caller waits and asks again. See assignPermissionSetDuringInstall above for the
     * system mode justification, which applies here too.
     *
     * @param userId the person who installed or upgraded the package
     * @param roleDeveloperName the DeveloperName of one of the five packaged roles
     * @return true when the person now holds the role, false when the role is not ready
     */
    public static Boolean tryAssignRoleDuringInstall(Id userId, String roleDeveloperName) {
        if (userId == null || !new Set<String>(ROLE_DEVELOPER_NAMES).contains(roleDeveloperName)) {
            return false;
        }
        PermissionSetGroup groupRecord = groupSelector.selectByDeveloperNameInSystemMode(
            roleDeveloperName
        );
        if (groupRecord == null || !READY_STATUS.equalsIgnoreCase(groupRecord.Status)) {
            return false;
        }
        if (assignmentSelector.countAssignmentInSystemMode(groupRecord.Id, userId) > 0) {
            return true;
        }
        Database.insert(
            new List<PermissionSetAssignment>{
                new PermissionSetAssignment(
                    AssigneeId = userId,
                    PermissionSetGroupId = groupRecord.Id
                )
            },
            true,
            AccessLevel.SYSTEM_MODE
        );
        return true;
    }

    /**
     * Takes one role away from one person. Removing a role the person does not hold
     * changes nothing and is not an error.
     *
     * @param userId the person to take the role from
     * @param roleDeveloperName the DeveloperName of one of the five packaged roles
     */
    public static void removeRole(Id userId, String roleDeveloperName) {
        removeRole(new Set<Id>{ userId }, roleDeveloperName);
    }

    /**
     * Takes one role away from a set of people, in a single DML operation.
     *
     * @param userIds the people to take the role from
     * @param roleDeveloperName the DeveloperName of one of the five packaged roles
     */
    public static void removeRole(Set<Id> userIds, String roleDeveloperName) {
        PermissionSetGroup groupRecord = requireReadyRole(roleDeveloperName);
        Set<Id> targets = requireChosenPeople(userIds);

        List<PermissionSetAssignment> toDelete = assignmentSelector.selectByGroupIdsAndUserIds(
            new Set<Id>{ groupRecord.Id },
            targets
        );
        if (toDelete.isEmpty()) {
            return;
        }
        if (ADMIN_ROLE.equals(groupRecord.DeveloperName)) {
            // Only the people who can still sign in count: removing a deactivated admin
            // must not be refused just because their assignment row is still there.
            Integer activeLosses = 0;
            for (PermissionSetAssignment assignment : toDelete) {
                if (assignment.Assignee.IsActive == true) {
                    activeLosses++;
                }
            }
            Integer remaining =
                assignmentSelector.countActiveAssignees(groupRecord.Id) - activeLosses;
            if (remaining < 1) {
                throw new AccessException(Label.Core_Access_ErrorLastAdmin);
            }
        }
        try {
            Database.delete(toDelete, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw logAndWrap(e, 'AccessService.removeRole', Label.Core_Access_ErrorUnexpected);
        }
    }

    /**
     * Loads the packaged role groups, keyed by DeveloperName.
     *
     * @return the groups this org has, of the five the package ships
     */
    private static Map<String, PermissionSetGroup> loadRoleGroups() {
        Map<String, PermissionSetGroup> groupsByName = new Map<String, PermissionSetGroup>();
        try {
            for (
                PermissionSetGroup groupRecord : groupSelector.selectByDeveloperNames(
                    new Set<String>(ROLE_DEVELOPER_NAMES)
                )
            ) {
                groupsByName.put(groupRecord.DeveloperName, groupRecord);
            }
        } catch (Exception e) {
            throw logAndWrap(e, 'AccessService.loadRoleGroups', Label.Core_Access_ErrorUnexpected);
        }
        return groupsByName;
    }

    /**
     * Checks that the role exists, is one of ours, and that the platform has finished
     * rebuilding it. A permission set group whose status is not Updated cannot be
     * assigned or unassigned: the platform rejects the DML.
     *
     * @param roleDeveloperName the DeveloperName to check
     * @return the group, ready to be assigned
     */
    private static PermissionSetGroup requireReadyRole(String roleDeveloperName) {
        if (
            String.isBlank(roleDeveloperName) ||
            !new Set<String>(ROLE_DEVELOPER_NAMES).contains(roleDeveloperName)
        ) {
            throw new AccessException(Label.Core_Access_ErrorRoleNotFound);
        }
        PermissionSetGroup groupRecord;
        try {
            groupRecord = groupSelector.selectByDeveloperName(roleDeveloperName);
        } catch (Exception e) {
            throw logAndWrap(
                e,
                'AccessService.requireReadyRole',
                Label.Core_Access_ErrorUnexpected
            );
        }
        if (groupRecord == null) {
            throw new AccessException(Label.Core_Access_ErrorRoleNotFound);
        }
        if (!READY_STATUS.equalsIgnoreCase(groupRecord.Status)) {
            throw new AccessException(Label.Core_Access_ErrorGroupNotReady);
        }
        return groupRecord;
    }

    /**
     * Checks that at least one person was actually chosen, and drops any empty entry.
     *
     * @param userIds the people the caller chose
     * @return the same people, without blanks
     */
    private static Set<Id> requireChosenPeople(Set<Id> userIds) {
        Set<Id> chosen = new Set<Id>();
        if (userIds != null) {
            for (Id userId : userIds) {
                if (userId != null) {
                    chosen.add(userId);
                }
            }
        }
        if (chosen.isEmpty()) {
            throw new AccessException(Label.Core_Access_ErrorInvalidInput);
        }
        return chosen;
    }

    /**
     * Checks that every chosen person exists and can still sign in.
     *
     * @param userIds the people the caller chose
     * @return the same people, confirmed active
     */
    private static Set<Id> requireActiveUsers(Set<Id> userIds) {
        return requireActiveUserMap(userIds).keySet();
    }

    /**
     * Checks that every chosen person exists and can still sign in, keeping their names.
     *
     * @param userIds the people the caller chose
     * @return the same people, confirmed active, by Id
     */
    private static Map<Id, User> requireActiveUserMap(Set<Id> userIds) {
        Set<Id> requested = requireChosenPeople(userIds);
        Map<Id, User> found;
        try {
            found = new Map<Id, User>(userSelector.selectActiveByIds(requested));
        } catch (Exception e) {
            throw logAndWrap(
                e,
                'AccessService.requireActiveUsers',
                Label.Core_Access_ErrorUnexpected
            );
        }
        if (found.size() != requested.size()) {
            throw new AccessException(Label.Core_Access_ErrorUserNotFound);
        }
        return found;
    }

    /**
     * Writes a failure to the Error Log and turns it into something the page can show.
     *
     * @param e the failure
     * @param context where it happened
     * @param message the plain language message for the person using the page
     * @return the exception for the caller to throw
     */
    private static AccessException logAndWrap(Exception e, String context, String message) {
        if (e instanceof AccessException) {
            return (AccessException) e;
        }
        ErrorLogger.log(e, context);
        AccessException wrapped = new AccessException(message);
        wrapped.initCause(e);
        return wrapped;
    }
}
