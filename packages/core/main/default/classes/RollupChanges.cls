/**
 * Which target records a save marks for recalculation (canonical model R-R11), for BarnCRM's own
 * rollup engine (rollup proposal, Part 2 section 4, "Collecting affected parents").
 *
 * - A save of a definition's source marks the targets its records reach, from the new values and,
 *   on an update, from the old ones too, so a record moved to another parent leaves the old total
 *   and joins the new one. An update marks only when an attribute the definition reads changed:
 *   the source, order-by and fiscal date attributes, a path attribute, or one the filter tests.
 * - A delete marks the old targets once the rows are gone; an undelete marks them again.
 * - Rows under a changed parent, which no trigger of their own reports (a gift's status read by
 *   the fund totals, a gift's allocations deleted with it), are `RollupDependents`.
 * - A person who joins or leaves a household (`HouseholdService.membershipChangeOf`), or who
 *   survives a merge, marks the households on both sides for every definition that reaches its
 *   target through a household token.
 *
 * Marking too much costs a recalculation and nothing else, because the engine recomputes; marking
 * too little leaves a total wrong until the nightly run. So the collector marks every alternative
 * of a path, not only the one that resolves.
 *
 * Paths are resolved here, not by `RollupPath.resolveTargets`, which keys its answer by record id
 * and so cannot hold the old and the new version of one record: a soft credit moved to another
 * person used to leave the household it left unmarked.
 *
 * DOCUMENTED EXCEPTION to user mode reads (plan Section 4.13): a path walked beyond its first
 * reference is read in system mode and without sharing, for the reason `RollupAggregator` gives.
 */
public without sharing class RollupChanges {
    private static final String LOG_CONTEXT = 'RollupChanges';

    /** Target records marked for recalculation, by target entity. */
    public class Marked {
        public Map<String, Set<Id>> idsByTarget = new Map<String, Set<Id>>();

        public void add(String targetObject, Set<Id> ids) {
            if (String.isBlank(targetObject) || ids == null) {
                return;
            }
            String key = targetObject.toLowerCase();
            for (Id recordId : ids) {
                if (recordId == null) {
                    continue;
                }
                if (!this.idsByTarget.containsKey(key)) {
                    this.idsByTarget.put(key, new Set<Id>());
                }
                this.idsByTarget.get(key).add(recordId);
            }
        }

        public void addAll(Marked other) {
            for (String targetObject : other.idsByTarget.keySet()) {
                this.add(targetObject, other.idsByTarget.get(targetObject));
            }
        }

        public Integer size() {
            Integer total = 0;
            for (Set<Id> ids : this.idsByTarget.values()) {
                total += ids.size();
            }
            return total;
        }

        public Boolean isEmpty() {
            return this.idsByTarget.isEmpty();
        }
    }

    /**
     * An insert, an update or an undelete.
     *
     * @param changedObject the entity saved
     * @param records the records saved
     * @param oldRecords the records before an update, or null
     * @param restored true for an undelete
     * @param definitions the active real-time definitions, of every source entity
     */
    public static Marked forSave(
        String changedObject,
        List<SObject> records,
        Map<Id, SObject> oldRecords,
        Boolean restored,
        List<Rollup_Definition__c> definitions
    ) {
        Marked marked = new Marked();
        Schema.SObjectType changedType = SettingsService.typeByName(changedObject);
        if (changedType == null || records == null || records.isEmpty()) {
            return marked;
        }
        Map<String, Schema.SObjectField> changedFields = fieldMap(changedType);
        for (Rollup_Definition__c definition : definitions) {
            RollupPath.Parsed path = pathOf(definition);
            if (path == null || !changedObject.equalsIgnoreCase(definition.Source_Object__c)) {
                continue;
            }
            List<SObject> touched = new List<SObject>();
            List<SObject> before = new List<SObject>();
            Set<String> read = localFields(readsOf(definition, path), changedFields);
            for (SObject record : records) {
                SObject previous = oldRecords == null ? null : oldRecords.get(record.Id);
                if (previous == null || changed(read, record, previous)) {
                    touched.add(record);
                    if (previous != null) {
                        before.add(previous);
                    }
                }
            }
            marked.add(definition.Target_Object__c, targetsOf(path, changedType, touched));
            marked.add(definition.Target_Object__c, targetsOf(path, changedType, before));
        }
        if (oldRecords != null || restored == true) {
            RollupDependents.forSave(changedType, records, oldRecords, definitions, marked);
        }
        markMembership(
            definitions,
            HouseholdService.membershipChangeOf(records, oldRecords),
            marked
        );
        return marked;
    }

    /**
     * After a delete: the old targets of the deleted records, the households their people left,
     * the households of merge survivors, and what `RollupDependents.beforeDelete` held.
     */
    public static Marked afterDelete(
        String changedObject,
        List<SObject> records,
        List<Rollup_Definition__c> definitions
    ) {
        Marked marked = new Marked();
        marked.addAll(RollupDependents.takeReadBeforeDelete());
        Schema.SObjectType changedType = SettingsService.typeByName(changedObject);
        if (changedType == null || records == null || records.isEmpty()) {
            return marked;
        }
        for (Rollup_Definition__c definition : definitions) {
            RollupPath.Parsed path = pathOf(definition);
            if (path != null && changedObject.equalsIgnoreCase(definition.Source_Object__c)) {
                marked.add(definition.Target_Object__c, targetsOf(path, changedType, records));
            }
        }
        HouseholdService.MembershipChange change = HouseholdService.membershipChangeOf(
            records,
            null
        );
        for (SObject record : records) {
            Object survivor = record.getPopulatedFieldsAsMap().get('MasterRecordId');
            if (survivor != null) {
                change.personIds.add((Id) survivor);
            }
        }
        change.householdIds.addAll(HouseholdService.getHouseholdIdsFor(change.personIds).values());
        change.householdIds.remove(null);
        markMembership(definitions, change, marked);
        return marked;
    }

    // ------------------------------------------------------------------------------- households

    /** Marks the households on both sides of a membership change, for token definitions. */
    private static void markMembership(
        List<Rollup_Definition__c> definitions,
        HouseholdService.MembershipChange change,
        Marked marked
    ) {
        if (change == null || change.householdIds.isEmpty()) {
            return;
        }
        Set<Id> people;
        for (Rollup_Definition__c definition : definitions) {
            RollupPath.Parsed path = pathOf(definition);
            if (path == null) {
                continue;
            }
            for (RollupPath.Branch branch : path.branches) {
                String token = tokenOf(branch);
                if (token == RollupPath.TOKEN_HOUSEHOLD) {
                    marked.add(definition.Target_Object__c, change.householdIds);
                } else if (token == RollupPath.TOKEN_HOUSEHOLD_MEMBERS) {
                    if (people == null) {
                        people = new Set<Id>(change.personIds);
                        for (
                            Set<Id> members : HouseholdService.getMemberPersonIds(
                                    change.householdIds
                                )
                                .values()
                        ) {
                            people.addAll(members);
                        }
                    }
                    marked.add(definition.Target_Object__c, people);
                }
            }
        }
    }

    // ------------------------------------------------------------------------------------ paths

    /** The definition's path, or null when it cannot be read (logged; R-R10 refuses it on save). */
    public static RollupPath.Parsed pathOf(Rollup_Definition__c definition) {
        try {
            return RollupPath.parse(definition.Relationship_Path__c);
        } catch (Exception unreadable) {
            ErrorLogger.log(unreadable, LOG_CONTEXT, definition.Id);
            return null;
        }
    }

    private static String tokenOf(RollupPath.Branch branch) {
        for (String segment : branch.segments) {
            if (RollupPath.TOKEN_HOUSEHOLD.equalsIgnoreCase(segment)) {
                return RollupPath.TOKEN_HOUSEHOLD;
            }
            if (RollupPath.TOKEN_HOUSEHOLD_MEMBERS.equalsIgnoreCase(segment)) {
                return RollupPath.TOKEN_HOUSEHOLD_MEMBERS;
            }
        }
        return null;
    }

    /** The targets these rows reach, through every alternative of the path. */
    public static Set<Id> targetsOf(
        RollupPath.Parsed path,
        Schema.SObjectType sourceType,
        List<SObject> rows
    ) {
        Set<Id> targets = new Set<Id>();
        if (path == null || rows == null || rows.isEmpty()) {
            return targets;
        }
        for (RollupPath.Branch branch : path.branches) {
            Set<Id> reached = reachedBy(branch.referencePrefix(), sourceType, rows);
            String token = tokenOf(branch);
            if (token == null) {
                targets.addAll(reached);
                continue;
            }
            Set<Id> households = new Set<Id>(HouseholdService.getHouseholdIdsFor(reached).values());
            households.remove(null);
            if (token == RollupPath.TOKEN_HOUSEHOLD) {
                targets.addAll(households);
            } else {
                for (Set<Id> members : HouseholdService.getMemberPersonIds(households).values()) {
                    targets.addAll(members);
                }
            }
        }
        targets.remove(null);
        return targets;
    }

    /**
     * The records the reference attributes before a token reach: the rows themselves when there
     * are none, the first reference read off each row, and further references walked by a query
     * of the record the first one names.
     */
    private static Set<Id> reachedBy(
        List<String> prefix,
        Schema.SObjectType sourceType,
        List<SObject> rows
    ) {
        Set<Id> reached = new Set<Id>();
        if (prefix.isEmpty()) {
            for (SObject row : rows) {
                reached.add(row.Id);
            }
            return reached;
        }
        Schema.SObjectField first = fieldMap(sourceType).get(prefix[0].toLowerCase());
        if (first == null) {
            return reached;
        }
        for (SObject row : rows) {
            Object value = row.get(first);
            if (value != null) {
                reached.add((Id) value);
            }
        }
        if (prefix.size() == 1 || reached.isEmpty()) {
            return reached;
        }
        List<Schema.SObjectType> referenced = first.getDescribe().getReferenceTo();
        if (referenced.isEmpty()) {
            return new Set<Id>();
        }
        List<String> rest = new List<String>();
        for (Integer i = 1; i < prefix.size(); i++) {
            rest.add(
                i == prefix.size() - 1 ? prefix[i] : RollupPath.relationshipNameFor(prefix[i])
            );
        }
        String expression = String.join(rest, '.');
        Set<Id> further = new Set<Id>();
        List<SObject> intermediates;
        try {
            // Segments are reference names RollupPath has already checked; ids are bound.
            intermediates = Database.queryWithBinds(
                'SELECT Id, ' +
                    expression +
                    ' FROM ' +
                    String.valueOf(referenced[0]) +
                    ' WHERE Id IN :reached',
                new Map<String, Object>{ 'reached' => reached },
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception unreadable) {
            ErrorLogger.log(unreadable, LOG_CONTEXT);
            return further;
        }
        for (SObject intermediate : intermediates) {
            Object value = valueAt(intermediate, expression);
            if (value != null) {
                further.add((Id) value);
            }
        }
        return further;
    }

    private static Object valueAt(SObject row, String path) {
        List<String> parts = path.split('\\.');
        SObject current = row;
        for (Integer i = 0; i < parts.size() - 1 && current != null; i++) {
            current = current.getSObject(parts[i]);
        }
        return current == null ? null : current.get(parts[parts.size() - 1]);
    }

    // ------------------------------------------------------------------------------- attributes

    /**
     * What a definition reads, as written on its source entity: plain attributes, and paths
     * through a relationship such as `Gift__r.Status__c`. A path attribute of more than one hop
     * is written as the path the engine queries, `Donor_Contact__r.AccountId`.
     */
    public static Set<String> readsOf(Rollup_Definition__c definition, RollupPath.Parsed path) {
        Set<String> reads = new Set<String>();
        for (
            String field : new List<String>{
                definition.Source_Field__c,
                definition.Order_By_Field__c,
                definition.Fiscal_Date_Field__c
            }
        ) {
            if (String.isNotBlank(field)) {
                reads.add(field.trim());
            }
        }
        reads.addAll(RollupFilterParser.fieldsOf(definition.Filter_JSON__c));
        for (RollupPath.Branch branch : path.branches) {
            List<String> prefix = branch.referencePrefix();
            List<String> parts = new List<String>();
            for (Integer i = 0; i < prefix.size(); i++) {
                parts.add(
                    i == prefix.size() - 1 ? prefix[i] : RollupPath.relationshipNameFor(prefix[i])
                );
            }
            if (!parts.isEmpty()) {
                reads.add(String.join(parts, '.'));
            }
        }
        return reads;
    }

    /** The attributes on the entity itself that these reads start from, in lower case. */
    public static Set<String> localFields(
        Set<String> reads,
        Map<String, Schema.SObjectField> fields
    ) {
        Set<String> local = new Set<String>();
        for (String read : reads) {
            String name = read.contains('.') ? referenceFieldFor(read.substringBefore('.')) : read;
            if (fields.containsKey(name.toLowerCase())) {
                local.add(name.toLowerCase());
            }
        }
        return local;
    }

    /** `Gift__r` is read through `Gift__c`, and `Account` through `AccountId`. */
    private static String referenceFieldFor(String relationshipName) {
        return relationshipName.endsWithIgnoreCase('__r')
            ? relationshipName.left(relationshipName.length() - 3) + '__c'
            : relationshipName + 'Id';
    }

    /** Whether any of these attributes differs between the two versions of a record. */
    public static Boolean changed(Set<String> fields, SObject record, SObject previous) {
        for (String field : fields) {
            if (record.get(field) != previous.get(field)) {
                return true;
            }
        }
        return false;
    }

    public static Map<String, Schema.SObjectField> fieldMap(Schema.SObjectType entity) {
        return entity.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
    }
}
