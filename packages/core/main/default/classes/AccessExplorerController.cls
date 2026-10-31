/**
 * The Access Explorer section of Org Optimizer (C-53, plan Section 6.1.1 item 7, D-154, admin
 * guide access-explorer.md): who can see or change what, and why.
 *
 * Read only. It queries profiles, permission sets, permission set groups, their assignments and
 * their object and field permissions in user mode (BarnCRM Admin carries View Setup and
 * Configuration) and never writes. Every method requires Manage BarnCRM Settings.
 *
 * A person's access is the sum of the permission sets assigned to them: their profile's own set,
 * each set assigned directly, and each group's calculated set, which Salesforce has already
 * reduced by the group's muting set. A group's components are read only to say which of them
 * give the access ("through"). Each call reads only what its view shows (one person's sets, one
 * object's grants, one page of people), so a large org is never read whole.
 */
public with sharing class AccessExplorerController {
    private static final String PERMISSION = 'Manage_BarnCRM_Settings';

    /** People listed per page on the By Kind of Record view. */
    @TestVisible
    private static final Integer PAGE_SIZE = 50;

    /** Most grants one kind of record lists; a longer list is cut and says so. */
    @TestVisible
    private static Integer maxGrants = 2000;

    private static final Integer SEARCH_LIMIT = 20;

    @TestVisible
    private static final String KIND_PROFILE = 'profile';
    @TestVisible
    private static final String KIND_GROUP = 'group';
    @TestVisible
    private static final String KIND_SET = 'permissionSet';

    /** The PermissionSet fields every label, kind and source needs. */
    private static final String SET_FIELDS =
        'SELECT Id, Label, Name, IsOwnedByProfile, Profile.Name, PermissionSetGroupId,' +
        ' PermissionSetGroup.MasterLabel, PermissionsViewAllData, PermissionsModifyAllData' +
        ' FROM PermissionSet WHERE ';

    /** Raised with a message the page shows as it is. */
    public class AccessExplorerException extends Exception {
    }

    /** One search result: a person or a permission set. */
    public class Choice {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String label;
        /** A person's profile, or a permission set's kind. */
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public Boolean isActive = true;
    }

    /** Object or field permissions, and what gives them. */
    public virtual class Flags {
        @AuraEnabled
        public Boolean read = false;
        @AuraEnabled
        public Boolean create = false;
        @AuraEnabled
        public Boolean edit = false;
        @AuraEnabled
        public Boolean del = false;
        @AuraEnabled
        public Boolean viewAll = false;
        @AuraEnabled
        public Boolean modifyAll = false;
        /** What gives it, names separated by a semicolon and a space. */
        @AuraEnabled
        public String grantedBy;

        private List<String> givers = new List<String>();

        public void add(Flags other) {
            read |= other.read;
            create |= other.create;
            edit |= other.edit;
            del |= other.del;
            viewAll |= other.viewAll;
            modifyAll |= other.modifyAll;
        }

        public void give(String giver) {
            if (!givers.contains(giver)) {
                givers.add(giver);
                grantedBy = String.join(givers, '; ');
            }
        }
    }

    /**
     * One place access comes from (a profile, permission set or group); also one grant of a kind
     * of record or field, with its active holders.
     */
    public class Grant extends Flags {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String kind;
        /** A group's permission sets, separated by a comma and a space. */
        @AuraEnabled
        public String through;
        @AuraEnabled
        public Integer activePeople = 0;
        @AuraEnabled
        public Boolean viewAllData = false;
        @AuraEnabled
        public Boolean modifyAllData = false;
    }

    /** One kind of record, one field, or one person, with its permissions. */
    public class Row extends Flags {
        /** An object's or field's API name, or a person's Id. */
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
        /** A field Salesforce does not let anyone restrict, such as Name. */
        @AuraEnabled
        public Boolean always = false;
    }

    /** What one person or one permission set can do. */
    public class SubjectAccess {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public Boolean isActive = true;
        @AuraEnabled
        public List<Grant> sources = new List<Grant>();
        @AuraEnabled
        public List<Row> objects = new List<Row>();
    }

    /** Who is given access to one kind of record or one field. */
    public class ObjectAccess {
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String fieldLabel;
        /** A field nobody who can read the record is kept from. */
        @AuraEnabled
        public Boolean always = false;
        @AuraEnabled
        public Boolean truncated = false;
        @AuraEnabled
        public List<Grant> grants = new List<Grant>();
    }

    /** One page of people, in name order. */
    public class PersonPage {
        @AuraEnabled
        public List<Row> rows = new List<Row>();
        @AuraEnabled
        public Boolean hasMore = false;
        @AuraEnabled
        public String afterName;
        @AuraEnabled
        public String afterId;
    }

    /** BarnCRM's own roles and permission sets, and the Tab Access Check. */
    public class Overview {
        @AuraEnabled
        public List<Grant> sets = new List<Grant>();
        @AuraEnabled
        public Boolean tabAccessCheckScheduled = false;
        @AuraEnabled
        public Datetime tabAccessCheckNextRun;
    }

    /**
     * People whose name contains the term, active first.
     * @param term at least two characters of a name
     * @return up to 20 people
     */
    @AuraEnabled
    public static List<Choice> searchPeople(String term) {
        try {
            requirePermission();
            List<Choice> choices = new List<Choice>();
            String pattern = likePattern(term);
            if (pattern == null) {
                return choices;
            }
            for (User person : [
                SELECT Id, Name, IsActive, Profile.Name
                FROM User
                WHERE Name LIKE :pattern
                WITH USER_MODE
                ORDER BY IsActive DESC, Name
                LIMIT :SEARCH_LIMIT
            ]) {
                Choice choice = new Choice();
                choice.id = person.Id;
                choice.label = person.Name;
                choice.detail = person.Profile?.Name;
                choice.isActive = person.IsActive;
                choices.add(choice);
            }
            return choices;
        } catch (Exception caught) {
            throw asUserError(caught, 'Access explorer people search');
        }
    }

    /**
     * Profiles, permission set groups and permission sets whose name contains the term.
     * @param term at least two characters of a name
     * @return up to 20, profiles first, then groups, then permission sets
     */
    @AuraEnabled
    public static List<Choice> searchPermissionSets(String term) {
        try {
            requirePermission();
            List<Choice> choices = new List<Choice>();
            String pattern = likePattern(term);
            if (pattern == null) {
                return choices;
            }
            for (
                PermissionSet permissionSet : querySets(
                    '(IsOwnedByProfile = FALSE AND Type = \'Regular\' AND Label LIKE :pattern)' +
                        ' OR (PermissionSetGroupId != NULL AND PermissionSetGroup.MasterLabel LIKE :pattern)' +
                        ' OR (IsOwnedByProfile = TRUE AND Profile.Name LIKE :pattern) LIMIT 20',
                    new Map<String, Object>{ 'pattern' => pattern }
                )
            ) {
                Choice choice = new Choice();
                choice.id = permissionSet.Id;
                choice.label = labelOf(permissionSet);
                choice.detail = kindOf(permissionSet);
                choices.add(choice);
            }
            return choices;
        } catch (Exception caught) {
            throw asUserError(caught, 'Access explorer permission set search');
        }
    }

    /**
     * Everything one person, or one profile, permission set or group, can at least read, and
     * what gives it.
     * @param subjectId a person's Id or a permission set's Id (a profile's or group's own set)
     * @return the subject's sources and one row per kind of record, by label
     */
    @AuraEnabled
    public static SubjectAccess getAccess(String subjectId) {
        try {
            requirePermission();
            SubjectAccess result = new SubjectAccess();
            Id parsed = toId(subjectId);
            List<PermissionSet> sources;
            if (parsed.getSObjectType() == User.SObjectType) {
                User person = requirePerson(parsed);
                sources = setsOfPerson(person);
                result.label = person.Name;
                result.detail = person.Profile?.Name;
                result.isActive = person.IsActive;
            } else {
                PermissionSet permissionSet = requireSet(parsed);
                sources = new List<PermissionSet>{ permissionSet };
                result.label = labelOf(permissionSet);
                result.detail = kindOf(permissionSet);
            }
            result.id = parsed;
            Map<Id, List<PermissionSet>> components = componentsOf(sources);
            Map<Id, Map<String, Flags>> byParent = new Map<Id, Map<String, Flags>>();
            for (ObjectPermissions permission : [
                SELECT
                    ParentId,
                    SobjectType,
                    PermissionsRead,
                    PermissionsCreate,
                    PermissionsEdit,
                    PermissionsDelete,
                    PermissionsViewAllRecords,
                    PermissionsModifyAllRecords
                FROM ObjectPermissions
                WHERE ParentId IN :allIds(sources, components) AND PermissionsRead = TRUE
                WITH USER_MODE
            ]) {
                keep(byParent, permission.ParentId, permission.SobjectType, flagsOf(permission));
            }
            Map<String, Row> rows = new Map<String, Row>();
            for (PermissionSet source : sources) {
                Grant described = grantOf(source);
                described.through = labelsOf(components.get(source.Id));
                result.sources.add(described);
                Map<String, Flags> own = byParent.get(source.Id);
                for (String objectType : own == null ? new Set<String>() : own.keySet()) {
                    if (!rows.containsKey(objectType)) {
                        rows.put(objectType, objectRow(objectType));
                    }
                    Row row = rows.get(objectType);
                    row.add(own.get(objectType));
                    row.give(giverText(source, components.get(source.Id), byParent, objectType));
                }
            }
            result.objects = sortedRows(rows.values());
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Access explorer access');
        }
    }

    /**
     * One kind of record's fields for one person or permission set, sorted by label.
     * @param subjectId a person's Id or a permission set's Id
     * @param objectName the object's API name
     * @return one row per field
     */
    @AuraEnabled
    public static List<Row> getFieldAccess(String subjectId, String objectName) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            Id parsed = toId(subjectId);
            List<PermissionSet> sources = parsed.getSObjectType() == User.SObjectType
                ? setsOfPerson(requirePerson(parsed))
                : new List<PermissionSet>{ requireSet(parsed) };
            Map<Id, List<PermissionSet>> components = componentsOf(sources);
            Map<Id, Map<String, Flags>> byParent = new Map<Id, Map<String, Flags>>();
            String objectType = described.getName();
            for (FieldPermissions permission : [
                SELECT ParentId, Field, PermissionsRead, PermissionsEdit
                FROM FieldPermissions
                WHERE
                    ParentId IN :allIds(sources, components)
                    AND SobjectType = :objectType
                    AND PermissionsRead = TRUE
                WITH USER_MODE
            ]) {
                Flags given = new Flags();
                given.read = true;
                given.edit = permission.PermissionsEdit;
                keep(byParent, permission.ParentId, permission.Field.substringAfter('.'), given);
            }
            List<Row> rows = new List<Row>();
            for (Schema.SObjectField token : described.fields.getMap().values()) {
                Schema.DescribeFieldResult field = token.getDescribe();
                Row row = newRow(field.getName(), field.getLabel());
                row.always = !field.isPermissionable();
                for (PermissionSet source : sources) {
                    Flags own = byParent.get(source.Id)?.get(row.name.toLowerCase());
                    if (own != null) {
                        row.add(own);
                        row.give(giverText(source, components.get(source.Id), byParent, row.name));
                    }
                }
                rows.add(row);
            }
            return sortedRows(rows);
        } catch (Exception caught) {
            throw asUserError(caught, 'Access explorer fields');
        }
    }

    /**
     * Every profile, permission set and group that gives access to one kind of record (View
     * All Data and Modify All Data included), or to one of its fields, with active holders.
     * @param objectName the object's API name
     * @param fieldName a field's API name, or blank for the kind of record itself
     * @return the grants, profiles first, then groups, then permission sets, each by name
     */
    @AuraEnabled
    public static ObjectAccess getObjectAccess(String objectName, String fieldName) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            Schema.DescribeFieldResult field = requireField(described, fieldName);
            ObjectAccess result = new ObjectAccess();
            result.objectLabel = described.getLabel();
            result.fieldLabel = field?.getLabel();
            result.always = field != null && !field.isPermissionable();
            if (!result.always) {
                Map<Id, Grant> grants = grantsFor(described, field, result);
                countHolders(grants);
                result.grants = sortedGrants(grants.values());
            }
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Access explorer object');
        }
    }

    /**
     * One page of the active people who have access to one kind of record or field, by name.
     * @param objectName the object's API name
     * @param fieldName a field's API name, or blank for the kind of record itself
     * @param afterName the previous page's last name, or blank for the first page
     * @param afterId the previous page's last Id, or blank for the first page
     * @return up to 50 people and where the next page starts
     */
    @AuraEnabled
    public static PersonPage getPeopleWithAccess(
        String objectName,
        String fieldName,
        String afterName,
        String afterId
    ) {
        try {
            requirePermission();
            Schema.DescribeSObjectResult described = requireObject(objectName);
            Schema.DescribeFieldResult field = requireField(described, fieldName);
            PersonPage page = new PersonPage();
            if (field != null && !field.isPermissionable()) {
                return page;
            }
            Map<Id, Grant> grants = grantsFor(described, field, new ObjectAccess());
            Set<Id> setIds = grants.keySet();
            Integer size = PAGE_SIZE + 1;
            List<User> people;
            if (String.isBlank(afterId)) {
                people = [
                    SELECT Id, Name
                    FROM User
                    WHERE
                        IsActive = TRUE
                        AND Id IN (
                            SELECT AssigneeId
                            FROM PermissionSetAssignment
                            WHERE PermissionSetId IN :setIds
                        )
                    WITH USER_MODE
                    ORDER BY Name, Id
                    LIMIT :size
                ];
            } else {
                Id lastId = toId(afterId);
                people = [
                    SELECT Id, Name
                    FROM User
                    WHERE
                        IsActive = TRUE
                        AND Id IN (
                            SELECT AssigneeId
                            FROM PermissionSetAssignment
                            WHERE PermissionSetId IN :setIds
                        )
                        AND (Name > :afterName
                        OR (Name = :afterName
                        AND Id > :lastId))
                    WITH USER_MODE
                    ORDER BY Name, Id
                    LIMIT :size
                ];
            }
            page.hasMore = people.size() > PAGE_SIZE;
            Map<Id, Row> rows = new Map<Id, Row>();
            for (Integer i = 0; i < Math.min(people.size(), PAGE_SIZE); i++) {
                rows.put(people[i].Id, newRow(people[i].Id, people[i].Name));
                page.afterName = people[i].Name;
                page.afterId = people[i].Id;
            }
            Set<Id> pageIds = rows.keySet();
            for (PermissionSetAssignment assignment : [
                SELECT AssigneeId, PermissionSetId
                FROM PermissionSetAssignment
                WHERE AssigneeId IN :pageIds AND PermissionSetId IN :setIds
                WITH USER_MODE
            ]) {
                Grant grant = grants.get(assignment.PermissionSetId);
                Row row = rows.get(assignment.AssigneeId);
                row.add(grant);
                row.give(grant.label);
            }
            page.rows = rows.values();
            return page;
        } catch (Exception caught) {
            throw asUserError(caught, 'Access explorer people');
        }
    }

    /**
     * BarnCRM's roles and permission sets with their active holders (direct holders, for a
     * permission set), and whether the hourly Tab Access Check is scheduled.
     * @return the overview
     */
    @AuraEnabled
    public static Overview getOverview() {
        try {
            requirePermission();
            Overview result = new Overview();
            String namespace = NamespaceUtil.prefix().removeEnd('__');
            Map<String, Object> binds = new Map<String, Object>{
                'prefix' => String.isBlank(namespace) ? null : namespace,
                'roles' => AccessService.ROLE_DEVELOPER_NAMES
            };
            Map<Id, Grant> roles = new Map<Id, Grant>();
            Map<Id, Grant> sets = new Map<Id, Grant>();
            for (
                PermissionSet permissionSet : querySets(
                    '(NamespacePrefix = :prefix AND Type = \'Regular\' AND Name LIKE \'BarnCRM%\')' +
                        ' OR (PermissionSetGroup.NamespacePrefix = :prefix' +
                        ' AND PermissionSetGroup.DeveloperName IN :roles)',
                    binds
                )
            ) {
                Grant row = grantOf(permissionSet);
                // Every packaged set is named BarnCRM_; LIKE treats the underscore as a wildcard.
                if (row.kind == KIND_GROUP) {
                    roles.put(row.id, row);
                } else if (permissionSet.Name.startsWith('BarnCRM_')) {
                    sets.put(row.id, row);
                }
            }
            countHolders(roles);
            countHolders(sets);
            result.sets.addAll(sortedGrants(roles.values()));
            result.sets.addAll(sortedGrants(sets.values()));
            result.tabAccessCheckScheduled = TabAccessScheduler.isScheduled();
            result.tabAccessCheckNextRun = ScheduledJobSelector.nextFireTime(
                TabAccessScheduler.JOB_NAME
            );
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Access explorer overview');
        }
    }

    /** The grants for one kind of record (with View All Data and Modify All Data) or field. */
    private static Map<Id, Grant> grantsFor(
        Schema.DescribeSObjectResult described,
        Schema.DescribeFieldResult field,
        ObjectAccess result
    ) {
        Map<Id, Flags> byParent = new Map<Id, Flags>();
        String objectType = described.getName();
        Integer cap = maxGrants + 1;
        if (field == null) {
            for (ObjectPermissions permission : [
                SELECT
                    ParentId,
                    PermissionsRead,
                    PermissionsCreate,
                    PermissionsEdit,
                    PermissionsDelete,
                    PermissionsViewAllRecords,
                    PermissionsModifyAllRecords
                FROM ObjectPermissions
                WHERE SobjectType = :objectType AND PermissionsRead = TRUE
                WITH USER_MODE
                LIMIT :cap
            ]) {
                byParent.put(permission.ParentId, flagsOf(permission));
            }
        } else {
            String fieldPath = objectType + '.' + field.getName();
            for (FieldPermissions permission : [
                SELECT ParentId, PermissionsEdit
                FROM FieldPermissions
                WHERE SobjectType = :objectType AND Field = :fieldPath AND PermissionsRead = TRUE
                WITH USER_MODE
                LIMIT :cap
            ]) {
                Flags given = new Flags();
                given.read = true;
                given.edit = permission.PermissionsEdit;
                byParent.put(permission.ParentId, given);
            }
        }
        Set<Id> parentIds = byParent.keySet();
        String everything = field == null
            ? ' OR PermissionsViewAllData = TRUE OR PermissionsModifyAllData = TRUE'
            : '';
        Map<Id, Grant> grants = new Map<Id, Grant>();
        for (
            PermissionSet permissionSet : querySets(
                '(Id IN :parentIds' + everything + ') LIMIT ' + cap,
                new Map<String, Object>{ 'parentIds' => parentIds }
            )
        ) {
            Grant row = grantOf(permissionSet);
            if (byParent.containsKey(row.id)) {
                row.add(byParent.get(row.id));
            }
            if (field == null && (row.viewAllData || row.modifyAllData)) {
                Flags all = new Flags();
                all.read = all.viewAll = true;
                all.create = all.edit = all.del = all.modifyAll = row.modifyAllData;
                row.add(all);
            }
            grants.put(row.id, row);
        }
        if (grants.size() > maxGrants) {
            result.truncated = true;
            List<Grant> kept = sortedGrants(grants.values());
            grants = new Map<Id, Grant>();
            for (Integer i = 0; i < maxGrants; i++) {
                grants.put(kept[i].id, kept[i]);
            }
        }
        return grants;
    }

    /** Fills in each grant's active direct holders with one summary query. */
    private static void countHolders(Map<Id, Grant> grants) {
        Set<Id> setIds = grants.keySet();
        for (AggregateResult counted : [
            SELECT PermissionSetId setId, COUNT(Id) people
            FROM PermissionSetAssignment
            WHERE PermissionSetId IN :setIds AND Assignee.IsActive = TRUE
            WITH USER_MODE
            GROUP BY PermissionSetId
        ]) {
            grants.get((Id) counted.get('setId')).activePeople = (Integer) counted.get('people');
        }
    }

    /** A person's sets: their profile's own set and every assignment, groups included. */
    private static List<PermissionSet> setsOfPerson(User person) {
        Set<Id> assigned = new Set<Id>();
        Id personId = person.Id;
        for (PermissionSetAssignment assignment : [
            SELECT PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :personId
            WITH USER_MODE
        ]) {
            assigned.add(assignment.PermissionSetId);
        }
        return querySets(
            'Id IN :assigned OR (IsOwnedByProfile = TRUE AND ProfileId = :profileId)',
            new Map<String, Object>{ 'assigned' => assigned, 'profileId' => person.ProfileId }
        );
    }

    /** Each group source's permission sets (muting sets left out), by the source's Id. */
    private static Map<Id, List<PermissionSet>> componentsOf(List<PermissionSet> sources) {
        Map<Id, Id> sourceByGroup = new Map<Id, Id>();
        for (PermissionSet source : sources) {
            if (source.PermissionSetGroupId != null) {
                sourceByGroup.put(source.PermissionSetGroupId, source.Id);
            }
        }
        Set<Id> groupIds = sourceByGroup.keySet();
        Map<Id, Set<Id>> insideByGroup = new Map<Id, Set<Id>>();
        Set<Id> componentIds = new Set<Id>();
        for (PermissionSetGroupComponent component : [
            SELECT PermissionSetGroupId, PermissionSetId
            FROM PermissionSetGroupComponent
            WHERE PermissionSetGroupId IN :groupIds
            WITH USER_MODE
        ]) {
            if (component.PermissionSetId?.getSObjectType() == PermissionSet.SObjectType) {
                if (!insideByGroup.containsKey(component.PermissionSetGroupId)) {
                    insideByGroup.put(component.PermissionSetGroupId, new Set<Id>());
                }
                insideByGroup.get(component.PermissionSetGroupId).add(component.PermissionSetId);
                componentIds.add(component.PermissionSetId);
            }
        }
        Map<Id, PermissionSet> components = new Map<Id, PermissionSet>(
            querySets(
                'Id IN :componentIds',
                new Map<String, Object>{ 'componentIds' => componentIds }
            )
        );
        Map<Id, List<PermissionSet>> bySource = new Map<Id, List<PermissionSet>>();
        for (Id groupId : insideByGroup.keySet()) {
            List<PermissionSet> inside = new List<PermissionSet>();
            for (PermissionSet component : components.values()) {
                if (insideByGroup.get(groupId).contains(component.Id)) {
                    inside.add(component);
                }
            }
            bySource.put(sourceByGroup.get(groupId), inside);
        }
        return bySource;
    }

    /** PermissionSet rows in user mode, profiles first, then groups, then sets, each by name. */
    private static List<PermissionSet> querySets(String condition, Map<String, Object> binds) {
        List<PermissionSet> found = Database.queryWithBinds(
            SET_FIELDS + condition,
            binds,
            AccessLevel.USER_MODE
        );
        Map<String, PermissionSet> byKey = new Map<String, PermissionSet>();
        for (PermissionSet permissionSet : found) {
            byKey.put(
                sortKey(kindOf(permissionSet), labelOf(permissionSet), permissionSet.Id),
                permissionSet
            );
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<PermissionSet> sorted = new List<PermissionSet>();
        for (String key : keys) {
            sorted.add(byKey.get(key));
        }
        return sorted;
    }

    private static void keep(
        Map<Id, Map<String, Flags>> byParent,
        Id parentId,
        String key,
        Flags given
    ) {
        if (!byParent.containsKey(parentId)) {
            byParent.put(parentId, new Map<String, Flags>());
        }
        byParent.get(parentId).put(key.toLowerCase(), given);
    }

    private static Set<Id> allIds(
        List<PermissionSet> sources,
        Map<Id, List<PermissionSet>> components
    ) {
        Set<Id> ids = new Map<Id, PermissionSet>(sources).keySet().clone();
        for (List<PermissionSet> inside : components.values()) {
            ids.addAll(new Map<Id, PermissionSet>(inside).keySet());
        }
        return ids;
    }

    /** A source's name, and for a group the sets inside it that give the same thing. */
    private static String giverText(
        PermissionSet source,
        List<PermissionSet> inside,
        Map<Id, Map<String, Flags>> byParent,
        String key
    ) {
        List<PermissionSet> giving = new List<PermissionSet>();
        for (PermissionSet component : inside == null ? new List<PermissionSet>() : inside) {
            if (byParent.get(component.Id)?.containsKey(key.toLowerCase()) == true) {
                giving.add(component);
            }
        }
        return giving.isEmpty()
            ? labelOf(source)
            : String.format(
                  System.Label.Core_AccessExplorer_Through,
                  new List<Object>{ labelOf(source), labelsOf(giving) }
              );
    }

    private static String labelsOf(List<PermissionSet> sets) {
        if (sets == null) {
            return null;
        }
        List<String> labels = new List<String>();
        for (PermissionSet permissionSet : sets) {
            labels.add(permissionSet.Label);
        }
        return String.join(labels, ', ');
    }

    private static Grant grantOf(PermissionSet permissionSet) {
        Grant row = new Grant();
        row.id = permissionSet.Id;
        row.label = labelOf(permissionSet);
        row.name = permissionSet.Name;
        row.kind = kindOf(permissionSet);
        row.viewAllData = permissionSet.PermissionsViewAllData == true;
        row.modifyAllData = permissionSet.PermissionsModifyAllData == true;
        return row;
    }

    private static Row newRow(String name, String label) {
        Row row = new Row();
        row.name = name;
        row.label = label;
        return row;
    }

    private static Flags flagsOf(ObjectPermissions permission) {
        Flags flags = new Flags();
        flags.read = permission.PermissionsRead;
        flags.create = permission.PermissionsCreate;
        flags.edit = permission.PermissionsEdit;
        flags.del = permission.PermissionsDelete;
        flags.viewAll = permission.PermissionsViewAllRecords;
        flags.modifyAll = permission.PermissionsModifyAllRecords;
        return flags;
    }

    /** A profile by its name, a group by its label, any other set by its label. */
    private static String labelOf(PermissionSet permissionSet) {
        if (permissionSet.IsOwnedByProfile && permissionSet.Profile?.Name != null) {
            return permissionSet.Profile.Name;
        }
        String groupLabel = permissionSet.PermissionSetGroup?.MasterLabel;
        return groupLabel == null ? permissionSet.Label : groupLabel;
    }

    private static String kindOf(PermissionSet permissionSet) {
        if (permissionSet.IsOwnedByProfile) {
            return KIND_PROFILE;
        }
        return permissionSet.PermissionSetGroupId != null ? KIND_GROUP : KIND_SET;
    }

    private static List<Grant> sortedGrants(List<Grant> grants) {
        Map<String, Grant> byKey = new Map<String, Grant>();
        for (Grant row : grants) {
            byKey.put(sortKey(row.kind, row.label, row.id), row);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<Grant> sorted = new List<Grant>();
        for (String key : keys) {
            sorted.add(byKey.get(key));
        }
        return sorted;
    }

    private static List<Row> sortedRows(List<Row> rows) {
        Map<String, Row> byKey = new Map<String, Row>();
        for (Row row : rows) {
            byKey.put(sortKey('', row.label, row.name), row);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<Row> sorted = new List<Row>();
        for (String key : keys) {
            sorted.add(byKey.get(key));
        }
        return sorted;
    }

    private static String sortKey(String kind, String label, String id) {
        String rank = kind == KIND_PROFILE ? '0' : kind == KIND_GROUP ? '1' : '2';
        return rank + (label == null ? '' : label.toLowerCase()) + '\u0000' + id;
    }

    /** A kind of record's row, named and labelled as describe has them. */
    private static Row objectRow(String objectType) {
        Schema.SObjectType token = NamespaceUtil.globalDescribe().get(objectType);
        if (token == null) {
            return newRow(objectType, objectType);
        }
        Schema.DescribeSObjectResult described = token.getDescribe(SObjectDescribeOptions.DEFERRED);
        return newRow(described.getName(), described.getLabel());
    }

    private static String likePattern(String term) {
        String trimmed = term == null ? '' : term.trim();
        return trimmed.length() < 2 ? null : '%' + trimmed + '%';
    }

    private static Id toId(String value) {
        try {
            return Id.valueOf(value);
        } catch (Exception invalid) {
            throw new AccessExplorerException(System.Label.Core_AccessExplorer_UnknownSubject);
        }
    }

    private static User requirePerson(Id userId) {
        List<User> found = [
            SELECT Id, Name, IsActive, ProfileId, Profile.Name
            FROM User
            WHERE Id = :userId
            WITH USER_MODE
            LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new AccessExplorerException(System.Label.Core_AccessExplorer_UnknownSubject);
        }
        return found[0];
    }

    private static PermissionSet requireSet(Id permissionSetId) {
        List<PermissionSet> found = permissionSetId.getSObjectType() == PermissionSet.SObjectType
            ? querySets('Id = :setId', new Map<String, Object>{ 'setId' => permissionSetId })
            : new List<PermissionSet>();
        if (found.isEmpty()) {
            throw new AccessExplorerException(System.Label.Core_AccessExplorer_UnknownSubject);
        }
        return found[0];
    }

    private static Schema.DescribeSObjectResult requireObject(String objectName) {
        Schema.SObjectType token = String.isBlank(objectName)
            ? null
            : NamespaceUtil.globalDescribe().get(objectName.trim());
        Schema.DescribeSObjectResult described = token?.getDescribe();
        if (described == null || !FindController.isOffered(described)) {
            throw new AccessExplorerException(
                String.format(
                    System.Label.Core_AccessExplorer_UnknownObject,
                    new List<Object>{ String.isBlank(objectName) ? '' : objectName }
                )
            );
        }
        return described;
    }

    private static Schema.DescribeFieldResult requireField(
        Schema.DescribeSObjectResult described,
        String fieldName
    ) {
        if (String.isBlank(fieldName)) {
            return null;
        }
        Schema.SObjectField token = described.fields.getMap().get(fieldName.trim());
        if (token == null) {
            throw new AccessExplorerException(
                String.format(
                    System.Label.Core_AccessExplorer_UnknownField,
                    new List<Object>{ fieldName }
                )
            );
        }
        return token.getDescribe();
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            throw new AccessExplorerException(System.Label.Core_AccessExplorer_PermissionRequired);
        }
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof AccessExplorerException)) {
            ErrorLogger.log(caught, context);
            message = System.Label.Core_AccessExplorer_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
