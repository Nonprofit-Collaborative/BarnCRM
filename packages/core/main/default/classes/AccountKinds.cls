/**
 * Tells which accounts are organizations (canonical model R-O4, R-O5, ADR-0141).
 *
 * Core ships no Organization record type. Organizations are the accounts of one record type
 * the org already has, named by `BarnCRM_Settings__c.Organization_Record_Type__c` (a developer
 * name), or of no record type when it holds `Master`. This class is the one place that reads
 * it, so Core and every module ask here rather than naming a record type.
 *
 * When nothing usable is stored (a new install before its first save, or a record type since
 * deactivated or deleted) the record type is detected: the active Account record types that
 * are neither person types nor named Household; one already used by an account first; then
 * Organization, Business_Account, Business and Default by developer name; then the first by
 * label; with none, `Master`. Detection only reads: it never creates, activates or shows a
 * record type.
 */
@NamespaceAccessible
public with sharing class AccountKinds {
    /** The stored value for "No record type": organizations are accounts with none. */
    @NamespaceAccessible
    public static final String NO_RECORD_TYPE = 'Master';

    /** The setting's key on `BarnCRM_Settings__c`. */
    @NamespaceAccessible
    public static final String KEY_ORGANIZATION_RECORD_TYPE = 'Organization_Record_Type__c';

    /** Developer names preferred, in this order, among the candidates detection weighs. */
    private static final List<String> PREFERRED_NAMES = new List<String>{
        'Organization',
        'Business_Account',
        'Business',
        'Default'
    };

    private static final String HOUSEHOLD_WORD = 'household';

    /**
     * At most this many candidates are asked "does any account use you" (one row each), so an
     * org with many Account record types cannot spend its query limit here. Candidates past
     * the cap count as unused.
     */
    private static final Integer IN_USE_CHECK_CAP = 20;

    /** Injected by the tests, in place of the org's own record types and their use. */
    @TestVisible
    private static List<Candidate> candidatesOverride;

    private static String cachedDetection;

    /**
     * The resolved name and the stored value it was resolved from, so the callers that ask once
     * per record (address capture, matching gifts) check the candidates once per transaction. A
     * change of the stored value resolves again.
     */
    private static String resolvedFor;
    private static String cachedResolution;

    /** One record type detection weighs. */
    @TestVisible
    private class Candidate {
        public String developerName;
        public String label;
        public Boolean inUse = false;

        public Candidate(String developerName, String label, Boolean inUse) {
            this.developerName = developerName;
            this.label = label;
            this.inUse = inUse == true;
        }
    }

    /**
     * The developer name of the organization record type in force, or `Master`. The stored
     * value when it is `Master` or still a candidate, otherwise the detected one. Never blank.
     */
    @NamespaceAccessible
    public static String organizationRecordTypeName() {
        String stored = storedValue();
        String key = stored == null ? '' : stored;
        if (cachedResolution != null && key.equals(resolvedFor)) {
            return cachedResolution;
        }
        String resolved;
        if (NO_RECORD_TYPE.equalsIgnoreCase(stored)) {
            resolved = NO_RECORD_TYPE;
        } else if (String.isNotBlank(stored) && isCandidate(stored)) {
            resolved = stored;
        } else {
            resolved = detectOrganizationRecordType();
        }
        resolvedFor = key;
        cachedResolution = resolved;
        return resolved;
    }

    /**
     * Whether an account whose record type has this developer name is an organization: the
     * chosen one, or, for `Master`, none (a blank name or the master's). For callers that
     * already hold the name, such as a query of `RecordType.DeveloperName`.
     */
    @NamespaceAccessible
    public static Boolean isOrganizationRecordTypeName(String developerName) {
        String chosen = organizationRecordTypeName();
        if (NO_RECORD_TYPE.equalsIgnoreCase(chosen)) {
            return String.isBlank(developerName) || NO_RECORD_TYPE.equalsIgnoreCase(developerName);
        }
        return String.isNotBlank(developerName) && chosen.equalsIgnoreCase(developerName);
    }

    /**
     * The record type a new organization is created with, or null for no record type (a
     * stored `Master`, or an org with no candidate).
     */
    @NamespaceAccessible
    public static Id organizationRecordTypeId() {
        String name = organizationRecordTypeName();
        if (NO_RECORD_TYPE.equalsIgnoreCase(name)) {
            return null;
        }
        Schema.RecordTypeInfo info = accountDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get(name);
        return info == null ? null : info.getRecordTypeId();
    }

    /**
     * Whether an account of this record type is an organization: its record type is the
     * chosen one, or, for `Master`, it has none (a blank Id or the master record type).
     */
    @NamespaceAccessible
    public static Boolean isOrganization(Id recordTypeId) {
        if (NO_RECORD_TYPE.equalsIgnoreCase(organizationRecordTypeName())) {
            if (recordTypeId == null) {
                return true;
            }
            Schema.RecordTypeInfo info = accountDescribe()
                .getRecordTypeInfosById()
                .get(recordTypeId);
            return info != null && info.isMaster();
        }
        return recordTypeId != null && recordTypeId == organizationRecordTypeId();
    }

    /**
     * What detection picks in this org now, whatever is stored (R-O5). Read once per
     * transaction: it asks each candidate whether an account uses it.
     */
    @NamespaceAccessible
    public static String detectOrganizationRecordType() {
        if (cachedDetection == null) {
            cachedDetection = rank(candidates());
        }
        return cachedDetection;
    }

    /**
     * The Account record types an administrator may choose for organizations, by label: active,
     * not the master, not a person type, and not named Household.
     */
    @NamespaceAccessible
    public static List<Schema.RecordTypeInfo> candidateRecordTypes() {
        Set<Id> personTypes = OrgShapeDetector.personRecordTypeIds();
        Map<String, Schema.RecordTypeInfo> byLabel = new Map<String, Schema.RecordTypeInfo>();
        for (Schema.RecordTypeInfo info : accountDescribe().getRecordTypeInfos()) {
            if (
                info.isActive() &&
                !info.isMaster() &&
                isOffered(
                    info.getDeveloperName(),
                    info.getName(),
                    personTypes.contains(info.getRecordTypeId())
                )
            ) {
                byLabel.put(info.getName().toLowerCase() + '|' + info.getDeveloperName(), info);
            }
        }
        List<String> keys = new List<String>(byLabel.keySet());
        keys.sort();
        List<Schema.RecordTypeInfo> chosen = new List<Schema.RecordTypeInfo>();
        for (String key : keys) {
            chosen.add(byLabel.get(key));
        }
        return chosen;
    }

    /** Whether this developer name is one of the candidates (case as Setup has it). */
    @NamespaceAccessible
    public static Boolean isCandidate(String developerName) {
        if (String.isBlank(developerName)) {
            return false;
        }
        for (Schema.RecordTypeInfo info : candidateRecordTypes()) {
            if (info.getDeveloperName() == developerName.trim()) {
                return true;
            }
        }
        return false;
    }

    /**
     * Stores the detected record type when nothing usable is stored: blank (a new install), or
     * a record type since deactivated, deleted or otherwise no longer a candidate. What install
     * and source deploy run (CorePostInstall), so the setting is never blank and the formula
     * field `Account.Is_Organization__c`, which reads the stored value, agrees with this class,
     * which reads a stale value as the detected one. `Master` and a candidate, the values an
     * administrator can save, are never overwritten.
     */
    @NamespaceAccessible
    public static void storeDetectedIfBlank() {
        String stored = storedValue();
        if (NO_RECORD_TYPE.equalsIgnoreCase(stored) || isCandidate(stored)) {
            return;
        }
        SettingsService.saveSystemValue(
            KEY_ORGANIZATION_RECORD_TYPE,
            detectOrganizationRecordType()
        );
    }

    /**
     * A record type is never offered for organizations when it is a person type or its
     * developer name or label contains Household (BarnCRM's own, NPSP's HH_Account and the
     * like), so a household can never be counted as an organization.
     */
    @TestVisible
    private static Boolean isOffered(String developerName, String label, Boolean isPersonType) {
        if (isPersonType == true) {
            return false;
        }
        String name = developerName == null ? '' : developerName.toLowerCase();
        String shown = label == null ? '' : label.toLowerCase();
        return !name.contains(HOUSEHOLD_WORD) && !shown.contains(HOUSEHOLD_WORD);
    }

    /**
     * The detection order (R-O5) over candidates that are already filtered: those in use when
     * any is, otherwise all; within them the preferred developer names in order; otherwise the
     * first by label; with no candidate, `Master`.
     */
    @TestVisible
    private static String rank(List<Candidate> candidates) {
        if (candidates == null || candidates.isEmpty()) {
            return NO_RECORD_TYPE;
        }
        List<Candidate> pool = new List<Candidate>();
        for (Candidate candidate : candidates) {
            if (candidate.inUse) {
                pool.add(candidate);
            }
        }
        if (pool.isEmpty()) {
            pool = candidates;
        }
        for (String preferred : PREFERRED_NAMES) {
            for (Candidate candidate : pool) {
                if (preferred.equalsIgnoreCase(candidate.developerName)) {
                    return candidate.developerName;
                }
            }
        }
        Candidate first;
        for (Candidate candidate : pool) {
            if (first == null || sortKey(candidate) < sortKey(first)) {
                first = candidate;
            }
        }
        return first.developerName;
    }

    private static String sortKey(Candidate candidate) {
        String label = candidate.label == null ? '' : candidate.label.toLowerCase();
        return label + '|' + candidate.developerName;
    }

    private static List<Candidate> candidates() {
        if (candidatesOverride != null) {
            return candidatesOverride;
        }
        List<Candidate> found = new List<Candidate>();
        Integer checked = 0;
        for (Schema.RecordTypeInfo info : candidateRecordTypes()) {
            Boolean used = false;
            if (checked < IN_USE_CHECK_CAP) {
                used = anyAccountUses(info.getRecordTypeId());
                checked++;
            }
            found.add(new Candidate(info.getDeveloperName(), info.getName(), used));
        }
        return found;
    }

    /**
     * Whether any account has this record type, as one row. System mode: the answer is an
     * org-wide fact that is stored org-wide, so it must not depend on whose sharing runs it.
     * Only the existence of a row is read, never a field of it.
     */
    private static Boolean anyAccountUses(Id recordTypeId) {
        return [
                SELECT COUNT()
                FROM Account
                WHERE RecordTypeId = :recordTypeId
                WITH SYSTEM_MODE
                LIMIT 1
            ] > 0;
    }

    private static String storedValue() {
        String stored = SettingsService.getSettings().Organization_Record_Type__c;
        return stored == null ? null : stored.trim();
    }

    private static Schema.DescribeSObjectResult accountDescribe() {
        return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED);
    }

    /** Clears the per-transaction detection, for tests that change the candidates. */
    @TestVisible
    private static void reset() {
        cachedDetection = null;
        candidatesOverride = null;
        resolvedFor = null;
        cachedResolution = null;
    }
}
