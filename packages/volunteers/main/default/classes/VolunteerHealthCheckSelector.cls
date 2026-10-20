/**
 * The reads behind the Volunteers Health Check findings (`VolunteersHealthCheckExtension`).
 *
 * `without sharing` and `WITH SYSTEM_MODE`, as `HealthCheckGivingSelector` reads gifts
 * (ADR-0021, ADR-0057): Volunteer Hours are Private, so a count limited by the administrator's
 * own sharing would be a wrong answer, not a narrower one. Each method asserts that the running
 * user may manage settings itself, not only its caller, because that permission is what makes an
 * organization-wide count safe to show. Each count stops at the cap it is given.
 */
public without sharing class VolunteerHealthCheckSelector {
    public class NotAllowedException extends Exception {
    }

    private static void requireManageSettings() {
        if (!HealthCheckService.canManageSettings()) {
            throw new NotAllowedException('Health Check findings need Manage BarnCRM Settings.');
        }
    }

    /** Submitted hours entered before this moment, oldest first. */
    public static List<Volunteer_Hours__c> hoursWaitingSince(Datetime enteredBefore, Integer cap) {
        requireManageSettings();
        return [
            SELECT Id, Name
            FROM Volunteer_Hours__c
            WHERE
                Status__c = :VolunteerHoursService.STATUS_SUBMITTED
                AND CreatedDate < :enteredBefore
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT :cap
        ];
    }

    /** Open shifts that ended before this moment, oldest first. */
    public static List<Volunteer_Shift__c> openShiftsEndedBefore(
        Datetime endedBefore,
        Integer cap
    ) {
        requireManageSettings();
        return [
            SELECT Id, Name
            FROM Volunteer_Shift__c
            WHERE Status__c = :ShiftScheduleService.STATUS_OPEN AND End_Time__c < :endedBefore
            WITH SYSTEM_MODE
            ORDER BY End_Time__c
            LIMIT :cap
        ];
    }

    /**
     * Active schedules that could be short of the horizon: running on or after today, starting by
     * the horizon, and with nothing created yet or created only to before `createdBefore`. The
     * caller compares each with its own End Date.
     */
    public static List<Shift_Schedule__c> schedulesShortOf(
        Date today,
        Date horizon,
        Date createdBefore,
        Integer cap
    ) {
        requireManageSettings();
        return [
            SELECT Id, Name, End_Date__c, Created_Through__c
            FROM Shift_Schedule__c
            WHERE
                Active__c = TRUE
                AND Start_Date__c <= :horizon
                AND (End_Date__c = NULL
                OR End_Date__c >= :today)
                AND (Created_Through__c = NULL
                OR Created_Through__c < :createdBefore)
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT :cap
        ];
    }

    /** The active holders of a permission set group, and which of them also hold a set directly. */
    public class GroupHolders {
        /** Each active holder of the group, by user Id and name. */
        public Map<Id, String> names = new Map<Id, String>();
        /** The active people assigned one of the sets itself, not through any group. */
        public Set<Id> holdingSetDirectly = new Set<Id>();
    }

    /**
     * The active people assigned this permission set group, and the active people assigned any of
     * these permission sets directly, in one read. The module's access sync gives the sets
     * directly, so in a healthy org this alone answers who is missing them; `setHoldersAmong` is
     * asked only about the group holders it leaves out, who may hold a set through another group.
     * One query rather than three keeps a whole Health Check run cheap.
     */
    public static GroupHolders groupHoldersWithSet(
        String groupName,
        Set<String> setNames,
        String namespace
    ) {
        requireManageSettings();
        GroupHolders holders = new GroupHolders();
        for (PermissionSetAssignment row : [
            SELECT AssigneeId, Assignee.Name, PermissionSetGroupId
            FROM PermissionSetAssignment
            WHERE
                Assignee.IsActive = TRUE
                AND ((PermissionSetGroup.DeveloperName = :groupName
                AND PermissionSetGroup.NamespacePrefix = :namespace)
                OR (PermissionSetGroupId = NULL
                AND PermissionSet.Name IN :setNames
                AND PermissionSet.NamespacePrefix = :namespace))
            WITH SYSTEM_MODE
            LIMIT 4000
        ]) {
            if (row.PermissionSetGroupId != null) {
                holders.names.put(row.AssigneeId, row.Assignee.Name);
            } else {
                holders.holdingSetDirectly.add(row.AssigneeId);
            }
        }
        return holders;
    }

    /** Of these people, those who hold any of the permission sets, directly or through a group. */
    public static Set<Id> setHoldersAmong(Set<Id> userIds, Set<String> setNames, String namespace) {
        requireManageSettings();
        Set<Id> groupIds = new Set<Id>();
        for (PermissionSetGroupComponent component : [
            SELECT PermissionSetGroupId
            FROM PermissionSetGroupComponent
            WHERE PermissionSet.Name IN :setNames AND PermissionSet.NamespacePrefix = :namespace
            WITH SYSTEM_MODE
        ]) {
            groupIds.add(component.PermissionSetGroupId);
        }
        Set<Id> holders = new Set<Id>();
        for (PermissionSetAssignment row : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE
                AssigneeId IN :userIds
                AND ((PermissionSet.Name IN :setNames
                AND PermissionSet.NamespacePrefix = :namespace)
                OR PermissionSetGroupId IN :groupIds)
            WITH SYSTEM_MODE
        ]) {
            holders.add(row.AssigneeId);
        }
        return holders;
    }

    /** The keys of the rollup definitions this package ships (29O). */
    public static Set<String> shippedRollupKeys(String packageName) {
        requireManageSettings();
        Set<String> keys = new Set<String>();
        for (Rollup_Definition_Default__mdt row : [
            SELECT Definition_Key__c
            FROM Rollup_Definition_Default__mdt
            WHERE Package__c = :packageName
            WITH SYSTEM_MODE
        ]) {
            keys.add(row.Definition_Key__c);
        }
        return keys;
    }

    /** The inactive definitions carrying these keys, by name. */
    public static List<Rollup_Definition__c> inactiveRollups(Set<String> keys) {
        requireManageSettings();
        return [
            SELECT Id, Name
            FROM Rollup_Definition__c
            WHERE Definition_Key__c IN :keys AND Active__c = FALSE
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 200
        ];
    }
}
