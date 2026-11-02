/**
 * The Field Access Manager (C-65, plan D-157, ADR-0156, canonical model Section 29ZP, admin
 * guide field-access-manager.md): gives or removes Read and Edit on fields and kinds of record,
 * for permission sets the organization made, previewed row by row and undoable.
 *
 * Only `ObjectPermissions` and `FieldPermissions` rows are written, in user mode, so the
 * platform's own Manage Profiles and Permission Sets check applies, and only for the sets the
 * admin chose and this class checked (R-FA2): rows held by a user license or permission set
 * license are never read. Those two objects are setup objects, which cannot share a transaction
 * with the data job and its journal (mixed DML), so the change is written here and recorded by
 * `FieldAccessRecordJob` in a transaction of its own.
 */
public with sharing class FieldAccessService {
    public static final String OPERATION_ACCESS = 'Access';
    public static final String READ = 'read';
    public static final String EDIT = 'edit';
    public static final String NONE = 'none';
    public static final String WHY_ASKED = 'asked';
    public static final String WHY_NEEDED = 'neededForFields';
    public static final String WHY_REMOVED_WITH_OBJECT = 'removedWithObject';
    public static final String OBJECT_ROW = 'ObjectPermissions';
    public static final String FIELD_ROW = 'FieldPermissions';

    public static final Integer MAX_SETS = 10;
    public static final Integer MAX_ITEMS = 500;
    /** The most rows one change writes: inside one transaction's DML and journal limits. */
    @TestVisible
    private static Integer maxRows = 2000;

    public static Integer rowLimit() {
        return maxRows;
    }
    private static final Integer SEARCH_LIMIT = 20;
    private static final String SETTINGS_PERMISSION = 'Manage_BarnCRM_Settings';
    /**
     * Permission sets the organization made: not a profile's, a group's, a muting, a packaged
     * set, or one BarnCRM ships (its access syncs manage those, so an edit would drift). Binds
     * :shipped.
     */
    private static final String ELIGIBLE =
        'IsOwnedByProfile = FALSE AND IsCustom = TRUE AND NamespacePrefix = NULL' +
        ' AND Type = \'Regular\' AND PermissionSetGroupId = NULL AND Name NOT IN :shipped';

    /** Set by a test to stand in for Manage Profiles and Permission Sets. */
    @TestVisible
    private static Boolean manageProfilesOverride;

    /** Raised with a message the page shows as it is. */
    public class FieldAccessException extends Exception {
    }

    /** Read and Edit, and for a kind of record its other four permissions. */
    public class Access {
        public Boolean read = false;
        public Boolean create = false;
        public Boolean edit = false;
        public Boolean del = false;
        public Boolean viewAll = false;
        public Boolean modifyAll = false;

        public Access copy() {
            Access other = new Access();
            other.read = read;
            other.create = create;
            other.edit = edit;
            other.del = del;
            other.viewAll = viewAll;
            other.modifyAll = modifyAll;
            return other;
        }

        public Boolean same(Access other) {
            return read == other.read &&
                create == other.create &&
                edit == other.edit &&
                del == other.del &&
                viewAll == other.viewAll &&
                modifyAll == other.modifyAll;
        }

        public Map<String, Object> toMap(Boolean isObject) {
            Map<String, Object> result = new Map<String, Object>{ 'read' => read, 'edit' => edit };
            if (isObject) {
                result.putAll(
                    new Map<String, Object>{
                        'create' => create,
                        'del' => del,
                        'viewAll' => viewAll,
                        'modifyAll' => modifyAll
                    }
                );
            }
            return result;
        }
    }

    /** One permission row the change writes. */
    public class Change {
        public Id setId;
        public String setLabel;
        public String objectName;
        public String objectLabel;
        /** The field's name without its object, or null for the kind of record. */
        public String fieldName;
        public String fieldLabel;
        public Id rowId;
        public Access now;
        public Access after;
        public String reason;

        public Boolean isObject() {
            return fieldName == null;
        }

        public String target() {
            return isObject() ? objectName : objectName + '.' + fieldName;
        }
    }

    /** What a change document would write. */
    public class Plan {
        public Map<String, Object> document;
        public List<Change> changes = new List<Change>();
        public Integer unchanged = 0;
        public Integer setCount = 0;
    }

    /** What an apply or an undo did, before it is recorded. */
    public class Result {
        public Integer changed = 0;
        public Integer refused = 0;
        public Integer kept = 0;
        public List<Map<String, Object>> entries = new List<Map<String, Object>>();
        public List<String> failures = new List<String>();
    }

    // -------------------------------------------------------------------------------------
    // Who may (R-FA2)
    // -------------------------------------------------------------------------------------

    /** Why the running user may not change field access, or null when they may. */
    public static String refusal() {
        if (!FeatureManagement.checkPermission(SETTINGS_PERMISSION)) {
            return System.Label.Core_FieldAccess_NeedsSettings;
        }
        Boolean manages = manageProfilesOverride;
        if (manages == null) {
            List<UserPermissionAccess> access = [
                SELECT PermissionsManageProfilesPermissionsets
                FROM UserPermissionAccess
                WITH USER_MODE
                LIMIT 1
            ];
            manages = !access.isEmpty() && access[0].PermissionsManageProfilesPermissionsets;
        }
        return manages ? null : System.Label.Core_FieldAccess_NeedsManageProfiles;
    }

    public static void enforce() {
        String reason = refusal();
        if (reason != null) {
            throw new FieldAccessException(reason);
        }
    }

    // -------------------------------------------------------------------------------------
    // Choosing
    // -------------------------------------------------------------------------------------

    /** Permission sets the organization made whose label contains the term, by label. */
    public static List<PermissionSet> searchSets(String term) {
        String trimmed = term == null ? '' : term.trim();
        if (trimmed.length() < 2) {
            return new List<PermissionSet>();
        }
        return Database.queryWithBinds(
            'SELECT Id, Label, Name, Description FROM PermissionSet WHERE ' +
                ELIGIBLE +
                ' AND Label LIKE :pattern ORDER BY Label LIMIT :howMany',
            new Map<String, Object>{
                'pattern' => '%' +
                trimmed +
                '%',
                'howMany' => SEARCH_LIMIT,
                'shipped' => BarnCRMShippedPermissionSets.NAMES
            },
            AccessLevel.USER_MODE
        );
    }

    /** The chosen sets, checked: every Id must be a set this tool may change (R-FA2). */
    public static Map<Id, PermissionSet> requireSets(List<Object> setIds) {
        Set<Id> ids = new Set<Id>();
        for (Object value : setIds == null ? new List<Object>() : setIds) {
            try {
                ids.add(Id.valueOf(String.valueOf(value)));
            } catch (Exception notAnId) {
                throw new FieldAccessException(System.Label.Core_FieldAccess_SetNotAllowed);
            }
        }
        if (ids.isEmpty()) {
            throw new FieldAccessException(System.Label.Core_FieldAccess_NoSets);
        }
        if (ids.size() > MAX_SETS) {
            throw new FieldAccessException(
                String.format(
                    System.Label.Core_FieldAccess_TooManySets,
                    new List<Object>{ MAX_SETS }
                )
            );
        }
        Map<Id, PermissionSet> found = new Map<Id, PermissionSet>(
            (List<PermissionSet>) Database.queryWithBinds(
                'SELECT Id, Label, Name FROM PermissionSet WHERE ' + ELIGIBLE + ' AND Id IN :ids',
                new Map<String, Object>{
                    'ids' => ids,
                    'shipped' => BarnCRMShippedPermissionSets.NAMES
                },
                AccessLevel.USER_MODE
            )
        );
        if (found.size() != ids.size()) {
            throw new FieldAccessException(System.Label.Core_FieldAccess_SetNotAllowed);
        }
        return found;
    }

    /** A kind of record this tool offers, or an error naming it. */
    public static Schema.DescribeSObjectResult requireObject(String objectName) {
        Schema.SObjectType token = String.isBlank(objectName)
            ? null
            : NamespaceUtil.globalDescribe().get(objectName.trim());
        Schema.DescribeSObjectResult described = token?.getDescribe();
        if (described == null || !FindController.isOffered(described)) {
            throw new FieldAccessException(
                String.format(
                    System.Label.Core_FieldAccess_UnknownObject,
                    new List<Object>{ objectName == null ? '' : objectName }
                )
            );
        }
        return described;
    }

    /** The fields Salesforce lets anyone give or take, by API name (R-FA3). */
    public static Map<String, Schema.DescribeFieldResult> permissionableFields(
        Schema.DescribeSObjectResult described
    ) {
        Map<String, Schema.DescribeFieldResult> result = new Map<String, Schema.DescribeFieldResult>();
        for (Schema.SObjectField token : described.fields.getMap().values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (field.isPermissionable()) {
                result.put(field.getName().toLowerCase(), field);
            }
        }
        return result;
    }

    /** A formula, roll-up summary or auto number field: Read only. */
    public static Boolean isReadOnly(Schema.DescribeFieldResult field) {
        return field.isCalculated() || field.isAutoNumber();
    }

    /** The current object rows of the sets for some kinds of record, by set and object. */
    public static Map<String, ObjectPermissions> objectRows(Set<Id> setIds, Set<String> objects) {
        Map<String, ObjectPermissions> result = new Map<String, ObjectPermissions>();
        for (ObjectPermissions row : [
            SELECT
                Id,
                ParentId,
                SobjectType,
                PermissionsRead,
                PermissionsCreate,
                PermissionsEdit,
                PermissionsDelete,
                PermissionsViewAllRecords,
                PermissionsModifyAllRecords
            FROM ObjectPermissions
            WHERE ParentId IN :setIds AND SobjectType IN :objects
            WITH USER_MODE
        ]) {
            result.put(key(row.ParentId, row.SobjectType), row);
        }
        return result;
    }

    /** The current field rows of the sets: for some fields, and every field of some objects. */
    public static Map<String, FieldPermissions> fieldRows(
        Set<Id> setIds,
        Set<String> targets,
        Set<String> wholeObjects
    ) {
        Map<String, FieldPermissions> result = new Map<String, FieldPermissions>();
        for (FieldPermissions row : [
            SELECT Id, ParentId, SobjectType, Field, PermissionsRead, PermissionsEdit
            FROM FieldPermissions
            WHERE ParentId IN :setIds AND (Field IN :targets OR SobjectType IN :wholeObjects)
            WITH USER_MODE
        ]) {
            result.put(key(row.ParentId, row.Field), row);
        }
        return result;
    }

    public static String key(Id setId, String target) {
        return setId + '|' + target.toLowerCase();
    }

    public static Access accessOf(ObjectPermissions row) {
        Access access = new Access();
        if (row != null) {
            access.read = row.PermissionsRead;
            access.create = row.PermissionsCreate;
            access.edit = row.PermissionsEdit;
            access.del = row.PermissionsDelete;
            access.viewAll = row.PermissionsViewAllRecords;
            access.modifyAll = row.PermissionsModifyAllRecords;
        }
        return access;
    }

    public static Access accessOf(FieldPermissions row) {
        Access access = new Access();
        if (row != null) {
            access.read = row.PermissionsRead;
            access.edit = row.PermissionsEdit;
        }
        return access;
    }

    // -------------------------------------------------------------------------------------
    // Preview (R-FA3 to R-FA5)
    // -------------------------------------------------------------------------------------

    /** One asked change, checked against describe. */
    private class Item {
        Schema.DescribeSObjectResult described;
        Schema.DescribeFieldResult field;
        String access;
    }

    /** Every row the change document would write, worked out from the rows there now. */
    public static Plan plan(String changeJson) {
        Map<String, Object> document = parse(changeJson);
        Map<Id, PermissionSet> sets = requireSets((List<Object>) document.get('setIds'));
        Map<String, Item> objectItems = new Map<String, Item>();
        Map<String, Item> fieldItems = new Map<String, Item>();
        Map<String, Schema.DescribeSObjectResult> objects = new Map<String, Schema.DescribeSObjectResult>();
        for (Item item : items(document)) {
            String objectName = item.described.getName();
            objects.put(objectName, item.described);
            if (item.field == null) {
                objectItems.put(objectName, item);
            } else {
                fieldItems.put(objectName + '.' + item.field.getName(), item);
            }
        }
        Set<String> removedObjects = new Set<String>();
        for (String objectName : objectItems.keySet()) {
            if (objectItems.get(objectName).access == NONE) {
                removedObjects.add(objectName);
            }
        }
        for (String target : fieldItems.keySet()) {
            Item item = fieldItems.get(target);
            if (item.access != NONE && removedObjects.contains(item.described.getName())) {
                throw new FieldAccessException(
                    String.format(
                        System.Label.Core_FieldAccess_Conflict,
                        new List<Object>{ item.described.getLabel() }
                    )
                );
            }
        }
        Map<String, ObjectPermissions> objectNow = objectRows(sets.keySet(), objects.keySet());
        Map<String, FieldPermissions> fieldNow = fieldRows(
            sets.keySet(),
            fieldItems.keySet(),
            removedObjects
        );
        Plan result = new Plan();
        result.document = document;
        result.setCount = sets.size();
        for (PermissionSet permissionSet : sets.values()) {
            for (String objectName : objects.keySet()) {
                planObject(
                    result,
                    permissionSet,
                    objects.get(objectName),
                    objectItems.get(objectName),
                    fieldItems,
                    objectNow,
                    fieldNow
                );
            }
        }
        return result;
    }

    private static void planObject(
        Plan result,
        PermissionSet permissionSet,
        Schema.DescribeSObjectResult described,
        Item objectItem,
        Map<String, Item> fieldItems,
        Map<String, ObjectPermissions> objectNow,
        Map<String, FieldPermissions> fieldNow
    ) {
        String objectName = described.getName();
        Boolean fieldsNeedRead = false;
        List<Change> fieldChanges = new List<Change>();
        for (String target : fieldItems.keySet()) {
            Item item = fieldItems.get(target);
            if (item.described.getName() != objectName) {
                continue;
            }
            FieldPermissions row = fieldNow.get(key(permissionSet.Id, target));
            Access after = new Access();
            after.read = item.access != NONE;
            after.edit = item.access == EDIT;
            fieldsNeedRead = fieldsNeedRead || after.read;
            Change change = newChange(permissionSet, described, item.field, row?.Id, accessOf(row));
            change.after = after;
            change.reason = WHY_ASKED;
            fieldChanges.add(change);
        }
        ObjectPermissions objectRow = objectNow.get(key(permissionSet.Id, objectName));
        Access now = accessOf(objectRow);
        Access after = now.copy();
        String reason = WHY_ASKED;
        if (objectItem != null && objectItem.access == NONE) {
            after = new Access();
            Map<String, Schema.DescribeFieldResult> fields = permissionableFields(described);
            String prefix = key(permissionSet.Id, objectName + '.');
            Set<String> asked = new Set<String>();
            for (String target : fieldItems.keySet()) {
                asked.add(target.toLowerCase());
            }
            for (String rowKey : fieldNow.keySet()) {
                FieldPermissions row = fieldNow.get(rowKey);
                if (!rowKey.startsWith(prefix) || asked.contains(row.Field.toLowerCase())) {
                    continue;
                }
                Schema.DescribeFieldResult field = fields.get(
                    row.Field.substringAfter('.').toLowerCase()
                );
                Change change = newChange(permissionSet, described, field, row.Id, accessOf(row));
                if (field == null) {
                    change.fieldName = row.Field.substringAfter('.');
                    change.fieldLabel = change.fieldName;
                }
                change.after = new Access();
                change.reason = WHY_REMOVED_WITH_OBJECT;
                fieldChanges.add(change);
            }
        } else if (objectItem != null) {
            after.read = true;
            after.edit = objectItem.access == EDIT;
            if (!after.edit) {
                after.del = false;
                after.modifyAll = false;
            }
        } else if (fieldsNeedRead && !now.read) {
            after.read = true;
            reason = WHY_NEEDED;
        }
        // A kind of record nobody asked about and the fields do not need is not counted.
        if (objectItem != null || reason == WHY_NEEDED) {
            Change objectChange = newChange(permissionSet, described, null, objectRow?.Id, now);
            objectChange.after = after;
            objectChange.reason = reason;
            add(result, objectChange);
        }
        for (Change change : fieldChanges) {
            add(result, change);
        }
    }

    private static void add(Plan result, Change change) {
        if (change.now.same(change.after)) {
            result.unchanged++;
        } else {
            result.changes.add(change);
        }
    }

    private static Change newChange(
        PermissionSet permissionSet,
        Schema.DescribeSObjectResult described,
        Schema.DescribeFieldResult field,
        Id rowId,
        Access now
    ) {
        Change change = new Change();
        change.setId = permissionSet.Id;
        change.setLabel = permissionSet.Label;
        change.objectName = described.getName();
        change.objectLabel = described.getLabel();
        change.fieldName = field?.getName();
        change.fieldLabel = field?.getLabel();
        change.rowId = rowId;
        change.now = now;
        return change;
    }

    private static Map<String, Object> parse(String changeJson) {
        try {
            Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(
                changeJson
            );
            if (document.get('version') != 1 || !(document.get('items') instanceof List<Object>)) {
                throw new FieldAccessException(System.Label.Core_FieldAccess_BadDocument);
            }
            return document;
        } catch (FieldAccessException known) {
            throw known;
        } catch (Exception unreadable) {
            throw new FieldAccessException(System.Label.Core_FieldAccess_BadDocument);
        }
    }

    private static List<Item> items(Map<String, Object> document) {
        List<Object> raw = (List<Object>) document.get('items');
        if (raw.isEmpty()) {
            throw new FieldAccessException(System.Label.Core_FieldAccess_NoItems);
        }
        if (raw.size() > MAX_ITEMS) {
            throw new FieldAccessException(
                String.format(
                    System.Label.Core_FieldAccess_TooManyItems,
                    new List<Object>{ MAX_ITEMS }
                )
            );
        }
        List<Item> result = new List<Item>();
        Map<String, Map<String, Schema.DescribeFieldResult>> fieldsByObject = new Map<String, Map<String, Schema.DescribeFieldResult>>();
        for (Object each : raw) {
            Map<String, Object> entry = each instanceof Map<String, Object>
                ? (Map<String, Object>) each
                : new Map<String, Object>();
            Item item = new Item();
            item.described = requireObject((String) entry.get('object'));
            item.access = String.valueOf(entry.get('access'));
            if (item.access != READ && item.access != EDIT && item.access != NONE) {
                throw new FieldAccessException(System.Label.Core_FieldAccess_BadDocument);
            }
            String fieldName = (String) entry.get('field');
            if (String.isNotBlank(fieldName)) {
                String objectName = item.described.getName();
                if (!fieldsByObject.containsKey(objectName)) {
                    fieldsByObject.put(objectName, permissionableFields(item.described));
                }
                String bare = fieldName.contains('.') ? fieldName.substringAfter('.') : fieldName;
                item.field = fieldsByObject.get(objectName).get(bare.trim().toLowerCase());
                if (item.field == null) {
                    throw new FieldAccessException(
                        String.format(
                            System.Label.Core_FieldAccess_FieldNotAllowed,
                            new List<Object>{ fieldName }
                        )
                    );
                }
                if (item.access == EDIT && isReadOnly(item.field)) {
                    throw new FieldAccessException(
                        String.format(
                            System.Label.Core_FieldAccess_ReadOnlyField,
                            new List<Object>{ item.field.getLabel() }
                        )
                    );
                }
            }
            result.add(item);
        }
        return result;
    }

    // -------------------------------------------------------------------------------------
    // Apply (R-FA5, R-FA6)
    // -------------------------------------------------------------------------------------

    /**
     * Works the change out again, refuses it when the count differs from the one confirmed,
     * writes it in user mode, and hands the journal to `FieldAccessRecordJob`.
     */
    public static Result apply(String changeJson, Integer confirmedCount) {
        Plan checked = plan(changeJson);
        Integer count = checked.changes.size();
        if (count == 0) {
            throw new FieldAccessException(System.Label.Core_FieldAccess_NothingToChange);
        }
        if (count > maxRows) {
            throw new FieldAccessException(
                String.format(
                    System.Label.Core_FieldAccess_TooManyRows,
                    new List<Object>{ count, maxRows }
                )
            );
        }
        if (confirmedCount != count) {
            throw new FieldAccessException(
                String.format(
                    System.Label.Core_FieldAccess_CountChanged,
                    new List<Object>{ count, confirmedCount == null ? 0 : confirmedCount }
                )
            );
        }
        List<Change> objectGrants = new List<Change>();
        List<Change> fieldGrants = new List<Change>();
        List<Change> fieldRemovals = new List<Change>();
        List<Change> objectRemovals = new List<Change>();
        for (Change change : checked.changes) {
            if (change.isObject()) {
                (change.after.read ? objectGrants : objectRemovals).add(change);
            } else {
                (change.after.read ? fieldGrants : fieldRemovals).add(change);
            }
        }
        Result result = new Result();
        save(objectGrants, result);
        save(fieldGrants, result);
        remove(fieldRemovals, result);
        remove(objectRemovals, result);
        FieldAccessRecordJob.recordApply(checked, confirmedCount, result);
        return result;
    }

    /** Inserts or updates rows that keep Read, journaling each. */
    public static void save(List<Change> changes, Result result) {
        if (changes.isEmpty()) {
            return;
        }
        List<Change> added = new List<Change>();
        List<Change> changed = new List<Change>();
        List<SObject> newRows = new List<SObject>();
        List<SObject> oldRows = new List<SObject>();
        for (Change change : changes) {
            (change.rowId == null ? added : changed).add(change);
            (change.rowId == null ? newRows : oldRows).add(toRow(change, change.after));
        }
        journal(
            added,
            Database.insert(newRows, false, AccessLevel.USER_MODE),
            ImportJournalService.ACTION_CREATED,
            result
        );
        journal(
            changed,
            Database.update(oldRows, false, AccessLevel.USER_MODE),
            ImportJournalService.ACTION_UPDATED,
            result
        );
    }

    private static void journal(
        List<Change> changes,
        List<Database.SaveResult> saved,
        String action,
        Result result
    ) {
        for (Integer i = 0; i < changes.size(); i++) {
            Change change = changes[i];
            if (saved[i].isSuccess()) {
                change.rowId = saved[i].getId();
                result.entries.add(entry(action, change));
                result.changed++;
            } else {
                refuse(change, saved[i].getErrors()[0].getMessage(), result);
            }
        }
    }

    /** Deletes rows left with no access: the platform keeps no empty row (R-FA6). */
    public static void remove(List<Change> changes, Result result) {
        if (changes.isEmpty()) {
            return;
        }
        List<Id> rowIds = new List<Id>();
        for (Change change : changes) {
            rowIds.add(change.rowId);
        }
        List<Database.DeleteResult> deleted = Database.delete(rowIds, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < changes.size(); i++) {
            if (deleted[i].isSuccess()) {
                result.entries.add(entry(ImportJournalService.ACTION_DELETED, changes[i]));
                result.changed++;
            } else {
                refuse(changes[i], deleted[i].getErrors()[0].getMessage(), result);
            }
        }
    }

    /** A row to insert (no row Id yet) or update, with the access given. */
    public static SObject toRow(Change change, Access access) {
        SObject row;
        if (change.isObject()) {
            row = change.rowId == null
                ? new ObjectPermissions(ParentId = change.setId, SobjectType = change.objectName)
                : new ObjectPermissions(Id = change.rowId);
            row.put('PermissionsRead', access.read);
            row.put('PermissionsCreate', access.create);
            row.put('PermissionsEdit', access.edit);
            row.put('PermissionsDelete', access.del);
            row.put('PermissionsViewAllRecords', access.viewAll);
            row.put('PermissionsModifyAllRecords', access.modifyAll);
            return row;
        }
        row = change.rowId == null
            ? new FieldPermissions(
                  ParentId = change.setId,
                  SobjectType = change.objectName,
                  Field = change.target()
              )
            : new FieldPermissions(Id = change.rowId);
        row.put('PermissionsRead', access.read);
        row.put('PermissionsEdit', access.edit);
        return row;
    }

    public static void refuse(Change change, String reason, Result result) {
        Map<String, Object> failed = entry(ImportJournalService.ACTION_FAILED, change);
        failed.put('reason', reason);
        result.entries.add(failed);
        result.refused++;
        result.failures.add(
            String.format(
                System.Label.Core_FieldAccess_RowRefused,
                new List<Object>{ change.setLabel, change.target(), reason }
            )
        );
    }

    // -------------------------------------------------------------------------------------
    // Undo (R-FA7)
    // -------------------------------------------------------------------------------------

    /** Why a change cannot be undone now, or null when it can. */
    public static String undoRefusal(Import_Batch__c job) {
        if (job == null || job.Operation__c != OPERATION_ACCESS) {
            return System.Label.Core_FieldAccess_UndoNotFound;
        }
        Boolean undoable =
            job.Status__c == ImportBatchService.STATUS_COMPLETE ||
            job.Status__c == ImportBatchService.STATUS_UNDO_FAILED;
        if (!undoable || job.Undo_Deadline__c == null) {
            return System.Label.Core_FieldAccess_UndoNotAllowed;
        }
        if (job.Undo_Deadline__c < Datetime.now()) {
            return String.format(
                System.Label.Core_FieldAccess_UndoWindowClosed,
                new List<Object>{ job.Undo_Deadline__c.format() }
            );
        }
        return null;
    }

    /**
     * Puts each journaled row back to its access before the change when it still has the
     * access the change left, in the reverse of the apply's order, and hands the result to
     * `FieldAccessRecordJob`. A row changed since is kept and journaled as not restored.
     */
    public static Result undo(Id jobId) {
        List<Import_Batch__c> found = [
            SELECT Id, Operation__c, Status__c, Undo_Deadline__c
            FROM Import_Batch__c
            WHERE Id = :jobId
            WITH USER_MODE
            LIMIT 1
        ];
        String reason = undoRefusal(found.isEmpty() ? null : found[0]);
        if (reason != null) {
            throw new FieldAccessException(reason);
        }
        List<Map<String, Object>> done = new List<Map<String, Object>>();
        for (
            Import_Journal__c page : ImportJournalService.pages(
                jobId,
                ImportJournalService.PHASE_COMMIT,
                ImportJournalService.MAX_PAGES_READ
            )
        ) {
            for (Map<String, Object> each : ImportJournalService.entries(page)) {
                if (each.get('action') != ImportJournalService.ACTION_FAILED) {
                    done.add(each);
                }
            }
        }
        Set<Id> setIds = new Set<Id>();
        Set<String> objects = new Set<String>();
        Set<String> fields = new Set<String>();
        for (Map<String, Object> each : done) {
            setIds.add(Id.valueOf((String) each.get('set')));
            String target = (String) each.get('target');
            (each.get('object') == OBJECT_ROW ? objects : fields).add(target);
        }
        Map<String, ObjectPermissions> objectNow = objectRows(setIds, objects);
        Map<String, FieldPermissions> fieldNow = fieldRows(setIds, fields, new Set<String>());
        // Index 0 puts back removed kinds of record, 1 removed fields, 2 granted fields, 3
        // granted kinds of record: the reverse of the apply's order.
        List<List<Change>> restores = new List<List<Change>>{
            new List<Change>(),
            new List<Change>(),
            new List<Change>(),
            new List<Change>()
        };
        Result result = new Result();
        for (Map<String, Object> each : done) {
            Boolean isObject = each.get('object') == OBJECT_ROW;
            Id setId = Id.valueOf((String) each.get('set'));
            String target = (String) each.get('target');
            String rowKey = key(setId, target);
            SObject row = isObject ? (SObject) objectNow.get(rowKey) : fieldNow.get(rowKey);
            Change change = new Change();
            change.setId = setId;
            change.setLabel = (String) each.get('setLabel');
            change.objectName = isObject ? target : target.substringBefore('.');
            change.fieldName = isObject ? null : target.substringAfter('.');
            change.rowId = row?.Id;
            change.now = isObject
                ? accessOf((ObjectPermissions) row)
                : accessOf((FieldPermissions) row);
            change.after = accessFrom(each.get('before'));
            Access left = accessFrom(each.get('after'));
            Boolean removed = each.get('action') == ImportJournalService.ACTION_DELETED;
            Boolean untouched = removed ? row == null : row != null && change.now.same(left);
            if (!untouched) {
                result.kept++;
                Map<String, Object> keptEntry = entry(
                    ImportJournalService.ACTION_NOT_RESTORED,
                    change
                );
                keptEntry.put('reason', System.Label.Core_FieldAccess_ChangedSince);
                result.entries.add(keptEntry);
                continue;
            }
            Integer slot = removed ? (isObject ? 0 : 1) : (isObject ? 3 : 2);
            restores[slot].add(change);
        }
        for (List<Change> step : restores) {
            List<Change> toSave = new List<Change>();
            List<Change> toRemove = new List<Change>();
            for (Change change : step) {
                (change.after.read ? toSave : toRemove).add(change);
            }
            save(toSave, result);
            remove(toRemove, result);
        }
        FieldAccessRecordJob.recordUndo(jobId, result);
        return result;
    }

    private static Access accessFrom(Object raw) {
        Map<String, Object> flags = raw instanceof Map<String, Object>
            ? (Map<String, Object>) raw
            : new Map<String, Object>();
        Access access = new Access();
        access.read = flags.get('read') == true;
        access.create = flags.get('create') == true;
        access.edit = flags.get('edit') == true;
        access.del = flags.get('del') == true;
        access.viewAll = flags.get('viewAll') == true;
        access.modifyAll = flags.get('modifyAll') == true;
        return access;
    }

    /** A journal entry (R-FA6). */
    public static Map<String, Object> entry(String action, Change change) {
        return new Map<String, Object>{
            'action' => action,
            'object' => change.isObject() ? OBJECT_ROW : FIELD_ROW,
            'id' => change.rowId == null ? null : String.valueOf(change.rowId),
            'set' => String.valueOf(change.setId),
            'setLabel' => change.setLabel,
            'target' => change.target(),
            'before' => change.now.toMap(change.isObject()),
            'after' => change.after.toMap(change.isObject())
        };
    }
}
