/**
 * The enrollment rules of the Programs module (canonical model Section 29Y, ADR-NEXT
 * `NEXT-programs-module.md`): which stages are open (R-EN2), refusing a second open enrollment
 * for the same person in the same program (R-EN2) and filling in the stage dates (R-EN3). The
 * trigger handlers decide which records each rule applies to.
 */
@NamespaceAccessible
public with sharing class EnrollmentService {
    @NamespaceAccessible
    public static final String STAGE_APPLIED = 'Applied';
    @NamespaceAccessible
    public static final String STAGE_ENROLLED = 'Enrolled';
    @NamespaceAccessible
    public static final String STAGE_COMPLETED = 'Completed';
    @NamespaceAccessible
    public static final String STAGE_WITHDRAWN = 'Withdrawn';

    /** Every stage, in the order a person moves through them. */
    @NamespaceAccessible
    public static final List<String> STAGES = new List<String>{
        STAGE_APPLIED,
        STAGE_ENROLLED,
        STAGE_COMPLETED,
        STAGE_WITHDRAWN
    };

    /** The stages of an enrollment that has not ended (R-EN2). */
    @NamespaceAccessible
    public static final Set<String> OPEN_STAGES = new Set<String>{ STAGE_APPLIED, STAGE_ENROLLED };

    /** The stages that end an enrollment, and fill in its End Date (R-EN3). */
    private static final Set<String> ENDED_STAGES = new Set<String>{
        STAGE_COMPLETED,
        STAGE_WITHDRAWN
    };

    /** The eligibility statuses that decide it, and fill in the Eligibility Date (R-EN6). */
    private static final Set<String> DECIDED_ELIGIBILITY = new Set<String>{
        'Eligible',
        'Not Eligible'
    };

    /** Whether an enrollment at this stage is open (Applied or Enrolled). */
    @NamespaceAccessible
    public static Boolean isOpen(String stage) {
        return OPEN_STAGES.contains(stage);
    }

    /**
     * R-EN2: refuses each open enrollment whose person already has another open enrollment in
     * the same program, counting every enrollment in the org, and the earlier ones in this list.
     * An enrollment that has ended, or names no program or no person, is not checked.
     */
    public static void refuseSecondOpenEnrollments(List<Enrollment__c> enrollments) {
        Set<Id> programIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> checkedIds = new Set<Id>();
        List<Enrollment__c> checked = new List<Enrollment__c>();
        for (Enrollment__c enrollment : enrollments) {
            if (!isOpen(enrollment.Stage__c) || keyOf(enrollment) == null) {
                continue;
            }
            checked.add(enrollment);
            programIds.add(enrollment.Program__c);
            if (enrollment.Contact__c != null) {
                contactIds.add(enrollment.Contact__c);
            } else {
                accountIds.add(enrollment.Account__c);
            }
            if (enrollment.Id != null) {
                checkedIds.add(enrollment.Id);
            }
        }
        if (checked.isEmpty()) {
            return;
        }

        Set<String> taken = new Set<String>();
        for (
            Enrollment__c existing : EnrollmentIntegritySelector.selectOpenFor(
                programIds,
                contactIds,
                accountIds
            )
        ) {
            if (!checkedIds.contains(existing.Id)) {
                taken.add(keyOf(existing));
            }
        }

        Map<Id, String> programNames = null;
        for (Enrollment__c enrollment : checked) {
            String key = keyOf(enrollment);
            if (!taken.contains(key)) {
                taken.add(key);
                continue;
            }
            if (programNames == null) {
                programNames = EnrollmentSelector.selectProgramNames(programIds);
            }
            String programName = programNames.get(enrollment.Program__c);
            enrollment.addError(
                String.format(
                    Label.Programs_Enrollment_AlreadyOpen,
                    new List<String>{
                        programName == null ? String.valueOf(enrollment.Program__c) : programName
                    }
                )
            );
        }
    }

    /**
     * R-EN3: an enrollment that becomes Enrolled gets today as an empty Start Date, and one that
     * becomes Completed or Withdrawn gets today as an empty End Date. A date already there is
     * kept. Before insert and before update, so the dates save with the stage.
     *
     * @param enrollments the records being saved
     * @param previousById the records as they were, or null on insert
     */
    public static void fillStageDates(
        List<Enrollment__c> enrollments,
        Map<Id, Enrollment__c> previousById
    ) {
        Date today = Date.today();
        for (Enrollment__c enrollment : enrollments) {
            Enrollment__c previous = previousById == null ? null : previousById.get(enrollment.Id);
            if (previous != null && previous.Stage__c == enrollment.Stage__c) {
                continue;
            }
            Boolean enrolls = enrollment.Stage__c == STAGE_ENROLLED;
            Boolean ends = ENDED_STAGES.contains(enrollment.Stage__c);
            if (enrolls && enrollment.Start_Date__c == null) {
                enrollment.Start_Date__c = today;
            }
            if (ends && enrollment.End_Date__c == null) {
                enrollment.End_Date__c = today;
            }
        }
    }

    /**
     * R-EN6: an enrollment whose eligibility is decided (Eligible or Not Eligible), when created
     * so or changed to it, gets today as its Eligibility Date when that is empty.
     */
    public static void fillEligibilityDates(
        List<Enrollment__c> enrollments,
        Map<Id, Enrollment__c> previousById
    ) {
        Date today = Date.today();
        for (Enrollment__c enrollment : enrollments) {
            Enrollment__c previous = previousById == null ? null : previousById.get(enrollment.Id);
            if (
                previous != null &&
                previous.Eligibility_Status__c == enrollment.Eligibility_Status__c
            ) {
                continue;
            }
            if (
                DECIDED_ELIGIBILITY.contains(enrollment.Eligibility_Status__c) &&
                enrollment.Eligibility_Date__c == null
            ) {
                enrollment.Eligibility_Date__c = today;
            }
        }
    }

    /** The program and person an enrollment names, as one key, or null when either is empty. */
    private static String keyOf(Enrollment__c enrollment) {
        Id person = enrollment.Contact__c != null ? enrollment.Contact__c : enrollment.Account__c;
        if (enrollment.Program__c == null || person == null) {
            return null;
        }
        return String.valueOf(enrollment.Program__c) + ':' + String.valueOf(person);
    }
}
