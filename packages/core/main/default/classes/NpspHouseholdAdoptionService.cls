/**
 * Adopts the Nonprofit Success Pack's household Accounts as BarnCRM households, in place, and
 * undoes an adoption (X-05, canonical model Section 29ZH, ADR-NEXT
 * `NEXT-npsp-household-adoption-in-core.md`, admin guide npsp-households.md).
 *
 * Preview first (R-HA2): what would be adopted is counted and sampled as the running user.
 * Starting a run, or an undo, is counted and confirmed, refused while another is running, and
 * hands the work to `NpspHouseholdAdoptionBatch`. NPSP is read only through
 * `NpspHouseholdSource`, so nothing here names NPSP and an org without it simply has nothing to
 * adopt. Every method requires Manage BarnCRM Settings (R-HA5).
 */
public with sharing class NpspHouseholdAdoptionService {
    /** Accounts one run adopts at most, as a bulk update's ceiling (R-BU2). */
    public static final Integer RUN_LIMIT = 48000;
    /** Candidates the preview shows. */
    public static final Integer SAMPLE_SIZE = 10;

    public static final String STATUS_ADOPTED = 'Adopted';
    public static final String STATUS_UNDONE = 'Undone';
    public static final String STATUS_NOT_RESTORED = 'Not Restored';

    @TestVisible
    private static final String BATCH_CLASS = 'NpspHouseholdAdoptionBatch';
    private static final Set<String> ACTIVE_JOB_STATUSES = new Set<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };

    @TestVisible
    private static Boolean permissionOverride;
    /** Test seam: true answers that a run is in progress. */
    @TestVisible
    private static Boolean runningOverride;

    /** Everything the panel shows. Plain JSON shape (plan 9.9). */
    public class Status {
        /** False when the org has no NPSP household marker at all. */
        @AuraEnabled
        public Boolean available = false;
        /** Why a run cannot start now (Junction membership, no Household record type), or null. */
        @AuraEnabled
        public String blockedReason;
        @AuraEnabled
        public Boolean running = false;
        /** Candidates, counted up to RUN_LIMIT plus one. */
        @AuraEnabled
        public Integer candidateCount = 0;
        /** True when more candidates exist than one run adopts. */
        @AuraEnabled
        public Boolean moreThanLimit = false;
        @AuraEnabled
        public Integer runLimit = RUN_LIMIT;
        @AuraEnabled
        public List<Candidate> sample = new List<Candidate>();
        /** The newest run, or null when nothing was ever adopted. */
        @AuraEnabled
        public Run lastRun;
    }

    /** One household the preview shows. */
    public class Candidate {
        @AuraEnabled
        public String accountId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String formalGreeting;
        @AuraEnabled
        public String informalGreeting;
        @AuraEnabled
        public String primaryContactName;
        @AuraEnabled
        public Integer contactCount = 0;
    }

    /** One run's journal, counted by status. */
    public class Run {
        @AuraEnabled
        public String runId;
        @AuraEnabled
        public Datetime adoptedAt;
        /** Rows still Adopted: what an undo would put back. */
        @AuraEnabled
        public Integer adopted = 0;
        @AuraEnabled
        public Integer undone = 0;
        @AuraEnabled
        public Integer notRestored = 0;
    }

    /**
     * True when the panel belongs on the settings page: NPSP is detected, the coexistence mode
     * is NPSP, or something was adopted earlier (so an undo is never hidden). ADR-0062: Core
     * names NPSP only where it applies.
     */
    public static Boolean isOffered() {
        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
        if (shape != null && shape.hasNpsp == true) {
            return true;
        }
        if (CoexistenceService.MODE_NPSP.equals(CoexistenceService.getCurrentMode())) {
            return true;
        }
        return [SELECT COUNT() FROM Household_Adoption__c WITH SYSTEM_MODE LIMIT 1] > 0;
    }

    public static Status getStatus() {
        requirePermission();
        Status status = new Status();
        NpspHouseholdSource source = NpspHouseholdSource.get();
        status.available = source.available();
        status.blockedReason = blockedReason();
        status.running = isRunning();
        if (status.available) {
            status.candidateCount = countCandidates(source);
            status.moreThanLimit = status.candidateCount > RUN_LIMIT;
            status.sample = sample(source);
        }
        status.lastRun = lastRun();
        return status;
    }

    /**
     * Starts an adoption run and answers its run id. `keepNames` marks every adopted household
     * Custom Name, so NPSP's name and greetings stand (R-HA3). Refused unless the candidates
     * counted now are no more than `confirmedCount` (R-HA2).
     */
    public static String start(Boolean keepNames, Integer confirmedCount) {
        requirePermission();
        String blocked = blockedReason();
        if (blocked != null) {
            throw UserErrors.message(blocked);
        }
        requireNotRunning();
        NpspHouseholdSource source = NpspHouseholdSource.get();
        Integer count = source.available() ? countCandidates(source) : 0;
        if (count == 0) {
            throw UserErrors.message(Label.Core_NpspAdoption_ErrorNothingToAdopt);
        }
        Integer runCount = Math.min(count, RUN_LIMIT);
        if (confirmedCount == null || runCount > confirmedCount) {
            throw UserErrors.message(
                String.format(
                    Label.Core_NpspAdoption_ErrorCountChanged,
                    new List<Object>{ runCount, confirmedCount == null ? 0 : confirmedCount }
                )
            );
        }
        String runId = UUID.randomUUID().toString();
        Database.executeBatch(
            NpspHouseholdAdoptionBatch.adopt(runId, keepNames != false, runCount),
            NpspHouseholdAdoptionBatch.CHUNK_SIZE
        );
        return runId;
    }

    /** Undoes one run (R-HA4). Refused unless the rows still adopted equal `confirmedCount`. */
    public static void undo(String runId, Integer confirmedCount) {
        requirePermission();
        requireNotRunning();
        Integer count = String.isBlank(runId) ? 0 : adoptedCount(runId);
        if (count == 0) {
            throw UserErrors.message(Label.Core_NpspAdoption_ErrorNothingToUndo);
        }
        if (confirmedCount == null || count != confirmedCount) {
            throw UserErrors.message(
                String.format(
                    Label.Core_NpspAdoption_ErrorCountChanged,
                    new List<Object>{ count, confirmedCount == null ? 0 : confirmedCount }
                )
            );
        }
        Database.executeBatch(
            NpspHouseholdAdoptionBatch.undo(runId),
            NpspHouseholdAdoptionBatch.CHUNK_SIZE
        );
    }

    /** Why a run cannot start, or null. */
    @TestVisible
    private static String blockedReason() {
        if (HouseholdService.householdRecordTypeId() == null) {
            return Label.Core_Households_ErrorRecordTypeMissing;
        }
        if (HouseholdService.isJunctionMode()) {
            return Label.Core_NpspAdoption_ErrorJunctionMode;
        }
        return null;
    }

    @TestVisible
    private static Boolean isRunning() {
        if (runningOverride != null) {
            return runningOverride;
        }
        return [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = :BATCH_CLASS AND Status IN :ACTIVE_JOB_STATUSES
                WITH SYSTEM_MODE
            ] > 0;
    }

    private static void requireNotRunning() {
        if (isRunning()) {
            throw UserErrors.message(Label.Core_NpspAdoption_ErrorRunning);
        }
    }

    private static Integer countCandidates(NpspHouseholdSource source) {
        String condition = source.condition();
        if (String.isBlank(condition)) {
            return 0;
        }
        return Database.countQueryWithBinds(
            'SELECT COUNT() FROM Account WHERE ' + condition + ' LIMIT ' + (RUN_LIMIT + 1),
            source.binds(),
            AccessLevel.USER_MODE
        );
    }

    private static List<Candidate> sample(NpspHouseholdSource source) {
        List<Candidate> result = new List<Candidate>();
        String condition = source.condition();
        if (String.isBlank(condition)) {
            return result;
        }
        Set<Id> ids = new Map<Id, SObject>(
                Database.queryWithBinds(
                    'SELECT Id FROM Account WHERE ' +
                        condition +
                        ' ORDER BY Id LIMIT ' +
                        SAMPLE_SIZE,
                    source.binds(),
                    AccessLevel.USER_MODE
                )
            )
            .keySet();
        List<NpspHouseholdSource.Household> households = source.read(ids);
        Set<Id> primaryIds = new Set<Id>();
        for (NpspHouseholdSource.Household household : households) {
            if (household.primaryContactId != null) {
                primaryIds.add(household.primaryContactId);
            }
        }
        Map<Id, Contact> primaries = new Map<Id, Contact>(
            [SELECT Id, Name FROM Contact WHERE Id IN :primaryIds WITH USER_MODE]
        );
        Map<Id, Integer> contactCounts = new Map<Id, Integer>();
        for (AggregateResult row : [
            SELECT AccountId, COUNT(Id) n
            FROM Contact
            WHERE AccountId IN :ids
            WITH USER_MODE
            GROUP BY AccountId
        ]) {
            contactCounts.put((Id) row.get('AccountId'), (Integer) row.get('n'));
        }
        for (NpspHouseholdSource.Household household : households) {
            Candidate candidate = new Candidate();
            candidate.accountId = household.accountId;
            candidate.name = household.name;
            candidate.formalGreeting = household.formalGreeting;
            candidate.informalGreeting = household.informalGreeting;
            Contact primary = primaries.get(household.primaryContactId);
            candidate.primaryContactName = primary == null ? null : primary.Name;
            Integer contacts = contactCounts.get(household.accountId);
            candidate.contactCount = contacts == null ? 0 : contacts;
            result.add(candidate);
        }
        return result;
    }

    /** The newest run and its counts, read in system mode: the journal is the package's own. */
    @TestVisible
    private static Run lastRun() {
        List<Household_Adoption__c> newest = [
            SELECT Run_Id__c, CreatedDate
            FROM Household_Adoption__c
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        if (newest.isEmpty()) {
            return null;
        }
        Run run = new Run();
        run.runId = newest[0].Run_Id__c;
        run.adoptedAt = newest[0].CreatedDate;
        run.adopted = adoptedCount(run.runId);
        run.undone = countWithStatus(run.runId, STATUS_UNDONE);
        run.notRestored = countWithStatus(run.runId, STATUS_NOT_RESTORED);
        return run;
    }

    private static Integer adoptedCount(String runId) {
        return countWithStatus(runId, STATUS_ADOPTED);
    }

    private static Integer countWithStatus(String runId, String status) {
        return [
            SELECT COUNT()
            FROM Household_Adoption__c
            WHERE Run_Id__c = :runId AND Status__c = :status
            WITH SYSTEM_MODE
        ];
    }

    private static void requirePermission() {
        Boolean allowed = permissionOverride != null
            ? permissionOverride
            : BarnCRMPermissions.canManageSettings();
        if (!allowed) {
            throw UserErrors.message(Label.Core_NpspAdoption_ErrorNoPermission);
        }
    }
}
