/**
 * Gives and takes the BarnCRM Tab permission sets, so a tool feature's tabs (Data Manager,
 * Import, Find, Bulk Update, Data Hygiene) show only while the feature is on (ADR-0124, edition
 * gates visibility).
 *
 * Each feature tab has a packaged permission set that shows that tab and nothing else. Its
 * audience is everyone who holds one of the permission sets the tab used to ride on, directly
 * or through a permission set group such as a BarnCRM role (`AUDIENCE`). Once the feature is
 * on the audience holds the tab set; while it is off nobody does. An upgraded org has every
 * feature on, so it keeps every tab it had: the install queues the first sync.
 *
 * The sync is a setup object write, which the platform will not mix with the setting write that
 * turned a feature on, so it always runs in a queued job (`requestSync`). It writes in system
 * mode: it is the package keeping its own permission sets in step with a feature an
 * administrator turned on, not a person assigning access, and it never touches a set outside
 * `AUDIENCE`'s keys. A large org is done a slice at a time, the job queuing itself again until
 * nothing is left, and a nightly run (`TabAccessScheduler`) catches people given a role outside
 * BarnCRM's Access page.
 *
 * A module that keeps its own permission sets with BarnCRM's roles uses the same audience
 * logic through `giveToHolders`, naming its sets and Core's (ADR-NEXT
 * `NEXT-rollup-builder-module.md`, D2); Core names no module set.
 */
@NamespaceAccessible
public with sharing class TabAccessService {
    public static final String DATA_MANAGER_TAB = 'BarnCRM_Tab_Data_Manager';
    public static final String IMPORT_TAB = 'BarnCRM_Tab_Import';
    public static final String FIND_TAB = 'BarnCRM_Tab_Find';
    public static final String BULK_UPDATE_TAB = 'BarnCRM_Tab_Bulk_Update';
    public static final String DATA_HYGIENE_TAB = 'BarnCRM_Tab_Data_Hygiene';

    private static final String ADMIN = 'BarnCRM_Admin';
    private static final String FIND_AND_EXPORT = 'BarnCRM_Find_And_Export';
    private static final String BULK_UPDATE = 'BarnCRM_Bulk_Update';
    private static final String BULK_DELETE = 'BarnCRM_Bulk_Delete';

    /** Each tab set, and the permission sets whose holders see that tab while it is on. */
    @TestVisible
    private static final Map<String, List<String>> AUDIENCE = new Map<String, List<String>>{
        DATA_MANAGER_TAB => new List<String>{ ADMIN, FIND_AND_EXPORT, BULK_UPDATE, BULK_DELETE },
        IMPORT_TAB => new List<String>{ ADMIN },
        FIND_TAB => new List<String>{ ADMIN, FIND_AND_EXPORT },
        BULK_UPDATE_TAB => new List<String>{ ADMIN, BULK_UPDATE, BULK_DELETE },
        DATA_HYGIENE_TAB => new List<String>{ ADMIN, FIND_AND_EXPORT }
    };

    /** How many assignments one run gives or takes, well inside the 10,000 DML rows. */
    @TestVisible
    private static Integer rowsPerRun = 5000;

    private static final String CONTEXT = 'TabAccessService.sync';

    /** Whether this transaction has already queued a sync. */
    private static Boolean requested = false;

    /**
     * Queues one sync for this transaction; asking again changes nothing. Never throws: a
     * switch that saved must not fail over its tabs, and the nightly run puts them right.
     */
    public static void requestSync() {
        if (requested) {
            return;
        }
        requested = true;
        try {
            System.enqueueJob(new Job());
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT);
        }
    }

    /**
     * One slice now, for a caller that already writes setup objects only, such as the install's
     * access job. Returns true when more is left for the queued or nightly run.
     */
    public static Boolean syncNow() {
        return syncOnce(rowsPerRun);
    }

    /** The queued sync: one slice, then itself again while more is left. */
    public class Job implements Queueable {
        public void execute(QueueableContext jobContext) {
            try {
                // A test cannot chain one queued job from another.
                if (syncOnce(rowsPerRun) && !Test.isRunningTest()) {
                    System.enqueueJob(new Job());
                }
            } catch (Exception e) {
                ErrorLogger.log(e, CONTEXT);
            }
        }
    }

    /**
     * Gives each tab set to its audience while its feature is on, and takes it from everyone
     * while the feature is off, up to `budget` assignments. Returns true when more is left.
     */
    public static Boolean syncOnce(Integer budget) {
        Map<String, Id> setIds = packagedSetIds();
        Map<Id, Set<Id>> groupIdsBySet = groupsContaining(setIds.values());
        Set<String> turnedOn = FeatureSwitchService.tabSetsOn();
        List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
        List<PermissionSetAssignment> toDelete = new List<PermissionSetAssignment>();
        Boolean more = false;
        for (String tabSet : AUDIENCE.keySet()) {
            Id tabSetId = setIds.get(tabSet);
            if (tabSetId == null) {
                continue;
            }
            Set<Id> wanted = turnedOn.contains(tabSet)
                ? holdersOf(AUDIENCE.get(tabSet), setIds, groupIdsBySet)
                : new Set<Id>();
            Map<Id, PermissionSetAssignment> held = directHolders(tabSetId);
            for (Id userId : wanted) {
                if (held.containsKey(userId)) {
                    continue;
                }
                if (toInsert.size() + toDelete.size() >= budget) {
                    more = true;
                    break;
                }
                toInsert.add(
                    new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = tabSetId)
                );
            }
            for (Id userId : held.keySet()) {
                if (wanted.contains(userId)) {
                    continue;
                }
                if (toInsert.size() + toDelete.size() >= budget) {
                    more = true;
                    break;
                }
                toDelete.add(held.get(userId));
            }
        }
        write(toInsert, toDelete, CONTEXT);
        return more;
    }

    /**
     * Gives the named permission set to every active person holding one of the audience sets,
     * directly or through a permission set group such as a BarnCRM role, up to `budget`
     * assignments. Never takes it away: a module's set may also be given by hand, to the person
     * who installed the module or to an integration user. For a module keeping its own sets with
     * BarnCRM's roles (ADR-NEXT `NEXT-rollup-builder-module.md`, D2); it names its set and the
     * audience, and Core names no module set. Written in system mode, as the tab sync is, and a
     * refused assignment is logged as a Warning under `context`. Returns true when more is left;
     * does nothing when the set is not in this org.
     */
    @NamespaceAccessible
    public static Boolean giveToHolders(
        String setName,
        List<String> audience,
        Integer budget,
        String context
    ) {
        Set<String> names = new Set<String>(audience);
        names.add(setName);
        Map<String, Id> setIds = packagedSetIds(names);
        Id setId = setIds.get(setName);
        if (setId == null) {
            return false;
        }
        Map<Id, Set<Id>> groupIdsBySet = groupsContaining(setIds.values());
        Set<Id> wanted = holdersOf(audience, setIds, groupIdsBySet);
        // Held already, directly or through a group, such as a module role that includes it.
        wanted.removeAll(holdersOf(new List<String>{ setName }, setIds, groupIdsBySet));
        List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
        for (Id userId : wanted) {
            if (toInsert.size() >= budget) {
                break;
            }
            toInsert.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = setId));
        }
        write(toInsert, new List<PermissionSetAssignment>(), context);
        return wanted.size() > toInsert.size();
    }

    /** Writes the assignments in system mode and logs each one refused as a Warning. */
    private static void write(
        List<PermissionSetAssignment> toInsert,
        List<PermissionSetAssignment> toDelete,
        String context
    ) {
        List<String> refusals = new List<String>();
        if (!toInsert.isEmpty()) {
            List<Database.SaveResult> saved = Database.insert(
                toInsert,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Database.SaveResult result : saved) {
                addErrors(refusals, result.isSuccess() ? null : result.getErrors());
            }
        }
        if (!toDelete.isEmpty()) {
            List<Database.DeleteResult> deleted = Database.delete(
                toDelete,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Database.DeleteResult result : deleted) {
                addErrors(refusals, result.isSuccess() ? null : result.getErrors());
            }
        }
        if (!refusals.isEmpty()) {
            ErrorLogger.logMessages(refusals, context, ErrorLogger.SEVERITY_WARNING);
        }
    }

    private static void addErrors(List<String> refusals, List<Database.Error> errors) {
        if (errors == null) {
            return;
        }
        for (Database.Error error : errors) {
            refusals.add(error.getMessage());
        }
    }

    /** This package's tab sets and audience sets, by name. */
    private static Map<String, Id> packagedSetIds() {
        Set<String> names = new Set<String>(AUDIENCE.keySet());
        for (List<String> sources : AUDIENCE.values()) {
            names.addAll(sources);
        }
        return packagedSetIds(names);
    }

    /** The named permission sets this product ships, by name. */
    private static Map<String, Id> packagedSetIds(Set<String> names) {
        String prefix = NamespaceUtil.prefix().removeEnd('__');
        String namespace = String.isBlank(prefix) ? null : prefix;
        Map<String, Id> ids = new Map<String, Id>();
        for (PermissionSet row : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :names AND NamespacePrefix = :namespace AND IsOwnedByProfile = FALSE
            WITH SYSTEM_MODE
        ]) {
            ids.put(row.Name, row.Id);
        }
        return ids;
    }

    /** The permission set groups, BarnCRM roles or an org's own, holding each set. */
    private static Map<Id, Set<Id>> groupsContaining(List<Id> setIds) {
        Map<Id, Set<Id>> groups = new Map<Id, Set<Id>>();
        for (PermissionSetGroupComponent component : [
            SELECT PermissionSetGroupId, PermissionSetId
            FROM PermissionSetGroupComponent
            WHERE PermissionSetId IN :setIds
            WITH SYSTEM_MODE
        ]) {
            if (!groups.containsKey(component.PermissionSetId)) {
                groups.put(component.PermissionSetId, new Set<Id>());
            }
            groups.get(component.PermissionSetId).add(component.PermissionSetGroupId);
        }
        return groups;
    }

    /** The active people holding any of the sets, directly or through a group. */
    private static Set<Id> holdersOf(
        List<String> sourceNames,
        Map<String, Id> setIds,
        Map<Id, Set<Id>> groupIdsBySet
    ) {
        Set<Id> sourceIds = new Set<Id>();
        Set<Id> groupIds = new Set<Id>();
        for (String name : sourceNames) {
            Id setId = setIds.get(name);
            if (setId == null) {
                continue;
            }
            sourceIds.add(setId);
            if (groupIdsBySet.containsKey(setId)) {
                groupIds.addAll(groupIdsBySet.get(setId));
            }
        }
        Set<Id> people = new Set<Id>();
        for (PermissionSetAssignment row : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE
                (PermissionSetId IN :sourceIds
                OR PermissionSetGroupId IN :groupIds)
                AND Assignee.IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            people.add(row.AssigneeId);
        }
        return people;
    }

    /** The people holding the tab set itself, with the assignment to take away. */
    private static Map<Id, PermissionSetAssignment> directHolders(Id tabSetId) {
        Map<Id, PermissionSetAssignment> held = new Map<Id, PermissionSetAssignment>();
        for (PermissionSetAssignment row : [
            SELECT Id, AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSetId = :tabSetId
            WITH SYSTEM_MODE
        ]) {
            held.put(row.AssigneeId, row);
        }
        return held;
    }
}
