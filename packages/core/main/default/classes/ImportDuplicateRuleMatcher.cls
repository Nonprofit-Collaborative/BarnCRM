/**
 * Asks the org's own active duplicate rules about the people and organizations of an import
 * chunk that the template's rule found nobody for (canonical model R-IT16, ADR-NEXT
 * `NEXT-data-transform-document.md`).
 *
 * Nothing here decides what a row is. The platform's matcher compares an unsaved record built
 * from the row with the records already there, as the org's rules say; this class keeps only
 * matches of the same object, reads them again in the running user's mode (so a record the user
 * cannot see is never matched) with the record types the caller allows, and hands each probe its
 * list. The import's row processor applies Several Matches (R-IT9) to that list.
 *
 * When the object has no active rule the user can see, or the matcher raises, the answer is
 * null and the caller matches by the template's rule alone. A test sets the answer through
 * `stubMatches`, because which records an org's rules call duplicates is the org's business
 * (as `DuplicateService` does for the duplicate scan).
 */
@NamespaceAccessible
public with sharing class ImportDuplicateRuleMatcher {
    /** How many records one call to the platform's matcher accepts. */
    @NamespaceAccessible
    public static final Integer MAX_RECORDS_PER_CALL = 50;

    private static final String CONTEXT = 'Import: matching through duplicate rules';

    /** The field types copied onto a probe: text a duplicate rule can compare. */
    private static final Set<Schema.DisplayType> COMPARED_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.URL,
        Schema.DisplayType.PICKLIST
    };

    /**
     * In a test, the record identifiers the rules match for a probe, keyed by the probe's last
     * name (a person) or name (an organization) folded to lower case. Null outside a test.
     */
    @TestVisible
    private static Map<String, List<Id>> stubMatches;

    /** In a test, the object has no active rule, or the matcher raises, as the platform can. */
    @TestVisible
    private static Boolean stubUnavailable = false;

    /** How many times the platform's matcher was called in this transaction. */
    @TestVisible
    private static Integer calls = 0;

    /**
     * An unsaved record of this object carrying the row's values, for the matcher to compare.
     * Only fields the object has, the user may read, and a rule can compare as text are copied;
     * anything else is left off rather than converted.
     *
     * @param type the object the entity is stored on
     * @param values the entity's values keyed by field API name
     * @param recordTypeId the record type the probe is of, or null
     */
    @NamespaceAccessible
    public static SObject probe(
        Schema.SObjectType type,
        Map<String, String> values,
        Id recordTypeId
    ) {
        SObject result = recordTypeId == null
            ? type.newSObject()
            : type.newSObject(recordTypeId, false);
        if (values == null) {
            return result;
        }
        Map<String, Schema.SObjectField> fields = type.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap();
        for (String fieldName : values.keySet()) {
            Schema.SObjectField field = fieldName == null
                ? null
                : fields.get(fieldName.toLowerCase());
            String value = values.get(fieldName);
            if (field == null || String.isBlank(value)) {
                continue;
            }
            Schema.DescribeFieldResult described = field.getDescribe();
            if (
                described.isAccessible() &&
                described.isCreateable() &&
                COMPARED_TYPES.contains(described.getType())
            ) {
                result.put(
                    field,
                    value.abbreviate(described.getLength() > 0 ? described.getLength() : 255)
                );
            }
        }
        return result;
    }

    /**
     * What the duplicate rules match for each probe, in the probes' order: the matched records of
     * the probes' own object that the user can see and, when `allowedRecordTypes` is given, whose
     * record type is one of them. Each record carries Id, CreatedDate and LastModifiedDate. Null
     * when the rules could not be asked: no active rule for the object, or the matcher raised.
     *
     * @param probes unsaved records, all of one object
     * @param allowedRecordTypes the record types a match may have, or null for any
     */
    @NamespaceAccessible
    public static List<List<SObject>> matchesFor(List<SObject> probes, Set<Id> allowedRecordTypes) {
        List<List<SObject>> result = new List<List<SObject>>();
        if (probes == null || probes.isEmpty()) {
            return result;
        }
        Schema.SObjectType type = probes[0].getSObjectType();
        Boolean active = hasActiveRule(type);
        if (active == false) {
            return null;
        }
        List<List<Id>> matchedIds = stubMatches != null ||
            stubUnavailable == true
            ? stubbed(probes)
            : asked(probes, type, active == true);
        if (matchedIds == null) {
            return null;
        }
        Set<Id> all = new Set<Id>();
        for (List<Id> ids : matchedIds) {
            all.addAll(ids);
        }
        Map<Id, SObject> visible = visible(type, all, allowedRecordTypes);
        for (List<Id> ids : matchedIds) {
            List<SObject> kept = new List<SObject>();
            for (Id matched : ids) {
                if (visible.containsKey(matched)) {
                    kept.add(visible.get(matched));
                }
            }
            result.add(kept);
        }
        return result;
    }

    /**
     * The one record of several to use: the most recently changed, the later created winning
     * a tie, as R-IT9 says; null when there are none.
     */
    @NamespaceAccessible
    public static SObject mostRecent(List<SObject> records) {
        SObject best;
        for (SObject record : records) {
            if (best == null || later(record, best)) {
                best = record;
            }
        }
        return best;
    }

    private static Boolean later(SObject record, SObject than) {
        Datetime changed = (Datetime) record.get('LastModifiedDate');
        Datetime bestChanged = (Datetime) than.get('LastModifiedDate');
        if (changed != bestChanged) {
            return changed > bestChanged;
        }
        return (Datetime) record.get('CreatedDate') > (Datetime) than.get('CreatedDate');
    }

    /**
     * Whether the object has an active duplicate rule the user can see: true or false, or null
     * when the user cannot read the rules at all, in which case the matcher is simply asked.
     * Asked first so a file loaded with no rule switched on logs no error for every chunk.
     */
    @NamespaceAccessible
    public static Boolean hasActiveRule(Schema.SObjectType type) {
        if (stubMatches != null || stubUnavailable == true) {
            return stubUnavailable != true;
        }
        String objectName = type.getDescribe().getName();
        try {
            return DuplicateSelector.objectsWithActiveRules(new Set<String>{ objectName })
                .contains(objectName);
        } catch (Exception cannotReadRules) {
            return null;
        }
    }

    /**
     * The platform's answer, 50 probes a call, as identifiers of the probes' own object. A
     * failure is logged only when a rule was known to be active, since otherwise it is the
     * platform saying there is none.
     */
    private static List<List<Id>> asked(
        List<SObject> probes,
        Schema.SObjectType type,
        Boolean ruleKnownActive
    ) {
        List<List<Id>> result = new List<List<Id>>();
        try {
            for (Integer start = 0; start < probes.size(); start += MAX_RECORDS_PER_CALL) {
                List<SObject> slice = new List<SObject>();
                for (
                    Integer i = start; i < probes.size() && i < start + MAX_RECORDS_PER_CALL; i++
                ) {
                    slice.add(probes[i]);
                }
                calls++;
                List<Datacloud.FindDuplicatesResult> found = Datacloud.FindDuplicates.findDuplicates(
                    slice
                );
                for (Integer i = 0; i < slice.size(); i++) {
                    result.add(i < found.size() ? idsOf(found[i], type) : new List<Id>());
                }
            }
        } catch (Exception caught) {
            // The caller then matches by the template's rule alone and says so in the run log.
            if (ruleKnownActive) {
                ErrorLogger.log(caught, CONTEXT);
            }
            return null;
        }
        return result;
    }

    private static List<Id> idsOf(Datacloud.FindDuplicatesResult found, Schema.SObjectType type) {
        List<Id> result = new List<Id>();
        for (Datacloud.DuplicateResult duplicate : found.getDuplicateResults()) {
            for (Datacloud.MatchResult match : duplicate.getMatchResults()) {
                for (Datacloud.MatchRecord record : match.getMatchRecords()) {
                    SObject matched = record.getRecord();
                    // A rule for people can also name records of other objects; only the
                    // probe's own object can be the row's person or organization.
                    if (
                        matched != null &&
                        matched.Id != null &&
                        matched.Id.getSObjectType() == type &&
                        !result.contains(matched.Id)
                    ) {
                        result.add(matched.Id);
                    }
                }
            }
        }
        return result;
    }

    private static List<List<Id>> stubbed(List<SObject> probes) {
        if (stubUnavailable == true) {
            return null;
        }
        List<List<Id>> result = new List<List<Id>>();
        for (SObject probe : probes) {
            Map<String, Object> given = probe.getPopulatedFieldsAsMap();
            String name = (String) (given.containsKey('LastName')
                ? given.get('LastName')
                : given.get('Name'));
            List<Id> ids = name == null ? null : stubMatches.get(name.toLowerCase());
            result.add(ids == null ? new List<Id>() : ids);
        }
        return result;
    }

    /** The matched records the user can see, of an allowed record type, read in user mode. */
    private static Map<Id, SObject> visible(
        Schema.SObjectType type,
        Set<Id> ids,
        Set<Id> allowedRecordTypes
    ) {
        Map<Id, SObject> result = new Map<Id, SObject>();
        if (ids.isEmpty()) {
            return result;
        }
        Boolean byType = allowedRecordTypes != null;
        String query =
            'SELECT Id, CreatedDate, LastModifiedDate FROM ' +
            type.getDescribe().getName() +
            ' WHERE Id IN :ids' +
            (byType ? ' AND RecordTypeId IN :types' : '');
        Map<String, Object> binds = new Map<String, Object>{ 'ids' => ids };
        if (byType) {
            binds.put('types', allowedRecordTypes);
        }
        for (SObject record : Database.queryWithBinds(query, binds, AccessLevel.USER_MODE)) {
            result.put(record.Id, record);
        }
        return result;
    }
}
