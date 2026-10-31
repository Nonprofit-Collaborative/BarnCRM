/**
 * What the Program Roster panel on a program calls (P-01, canonical model Section 29ZA).
 *
 * Counts the program's enrollments in each stage, lists its open enrollments (or all of them),
 * enrolls a person and changes an enrollment's stage, all in user mode. Saves go through the
 * enrollment automation like any other save, so one open enrollment per person per program
 * (R-EN2) and the stage dates (R-EN3) apply here too. Returns plain wrappers (plan Section 9.9).
 * Anything unexpected is recorded in the Error Log before it is reported (plan Section 7.2).
 */
public with sharing class ProgramRosterController {
    private static final String CONTEXT = 'Program roster panel';
    /** The most enrollments listed: a bound on the read; the Enrollments tab lists them all. */
    public static final Integer MAX_SHOWN = 200;
    /**
     * The field a record picker filters on to offer person accounts only, sent to the panel as
     * text and used only in a person account org.
     */
    private static final String PERSON_ACCOUNT_FILTER_FIELD = 'IsPersonAccount'; // detection-only: a record picker filter field, sent only after isPersonAccountOrg found person accounts

    public class EnrollmentRow {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String personName;
        @AuraEnabled
        public String stage;
        @AuraEnabled
        public Date startDate;
        @AuraEnabled
        public Date endDate;
    }

    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        /** For a stage: how many of the program's enrollments are at it. */
        @AuraEnabled
        public Integer count = 0;
        /** For a stage: whether it is open (Applied or Enrolled). */
        @AuraEnabled
        public Boolean open = false;
    }

    /** The panel's whole state. */
    public class Roster {
        @AuraEnabled
        public String programName;
        @AuraEnabled
        public List<Option> stages = new List<Option>();
        @AuraEnabled
        public List<EnrollmentRow> enrollments = new List<EnrollmentRow>();
        @AuraEnabled
        public Boolean showEnded = false;
        @AuraEnabled
        public Boolean moreThanShown = false;
        @AuraEnabled
        public Boolean canAdd = false;
        @AuraEnabled
        public Boolean canEdit = false;
        @AuraEnabled
        public Boolean hasPersonAccounts = false;
        @AuraEnabled
        public String personFilterField;
    }

    /** Not cacheable: the roster changes with every enrollment. */
    @AuraEnabled
    public static Roster getRoster(Id programId, Boolean showEnded) {
        if (programId == null) {
            throw badRequest(Label.Programs_Roster_ActionFailed);
        }
        try {
            return rosterFor(programId, showEnded == true);
        } catch (Exception failure) {
            throw report(failure, programId);
        }
    }

    /** Enrolls a person in the program: a Contact, or a person Account in such an org. */
    @AuraEnabled
    public static Roster enroll(Id programId, Id personId, String stage, Boolean showEnded) {
        if (programId == null) {
            throw badRequest(Label.Programs_Roster_ActionFailed);
        }
        if (personId == null) {
            throw badRequest(Label.Programs_Roster_PersonRequired);
        }
        Enrollment__c enrollment = new Enrollment__c(Program__c = programId);
        if (String.isNotBlank(stage)) {
            enrollment.Stage__c = checkedStage(stage);
        }
        if (personId.getSObjectType() == Contact.SObjectType) {
            enrollment.Contact__c = personId;
        } else {
            enrollment.Account__c = personId;
        }
        try {
            Database.insert(new List<Enrollment__c>{ enrollment }, true, AccessLevel.USER_MODE);
            return rosterFor(programId, showEnded == true);
        } catch (Exception failure) {
            throw report(failure, programId);
        }
    }

    /** Moves an enrollment to another stage; the stage dates fill in through the automation. */
    @AuraEnabled
    public static Roster setStage(Id enrollmentId, String stage, Boolean showEnded) {
        if (enrollmentId == null || String.isBlank(stage)) {
            throw badRequest(Label.Programs_Roster_ActionFailed);
        }
        String wanted = checkedStage(stage);
        try {
            Id programId = EnrollmentSelector.selectProgramIdOf(enrollmentId);
            if (programId == null) {
                throw badRequest(Label.Programs_Roster_ActionFailed);
            }
            Database.update(
                new List<Enrollment__c>{ new Enrollment__c(Id = enrollmentId, Stage__c = wanted) },
                true,
                AccessLevel.USER_MODE
            );
            return rosterFor(programId, showEnded == true);
        } catch (Exception failure) {
            throw report(failure, enrollmentId);
        }
    }

    // ------------------------------------------------------------------------------ helpers

    private static Roster rosterFor(Id programId, Boolean showEnded) {
        String programName = EnrollmentSelector.selectProgramNames(new Set<Id>{ programId })
            .get(programId);
        if (programName == null) {
            throw badRequest(Label.Programs_Roster_ActionFailed);
        }
        Roster roster = new Roster();
        roster.programName = programName;
        roster.showEnded = showEnded;

        Map<String, Integer> counts = EnrollmentSelector.countByStage(programId);
        Set<String> listed = new Set<String>();
        for (Schema.PicklistEntry entry : stageEntries()) {
            Option option = new Option();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            option.count = counts.containsKey(option.value) ? counts.get(option.value) : 0;
            option.open = EnrollmentService.isOpen(option.value);
            roster.stages.add(option);
            if (showEnded || option.open) {
                listed.add(option.value);
            }
        }

        List<Enrollment__c> found = EnrollmentSelector.selectRoster(
            programId,
            listed,
            MAX_SHOWN + 1
        );
        roster.moreThanShown = found.size() > MAX_SHOWN;
        for (Integer i = 0; i < found.size() && i < MAX_SHOWN; i++) {
            roster.enrollments.add(rowFor(found[i]));
        }

        Schema.DescribeSObjectResult describe = Enrollment__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        );
        roster.canAdd = describe.isCreateable();
        roster.canEdit = describe.isUpdateable();
        roster.hasPersonAccounts = HouseholdService.isPersonAccountOrg();
        roster.personFilterField = roster.hasPersonAccounts ? PERSON_ACCOUNT_FILTER_FIELD : null;
        return roster;
    }

    private static EnrollmentRow rowFor(Enrollment__c enrollment) {
        EnrollmentRow row = new EnrollmentRow();
        row.recordId = enrollment.Id;
        row.name = enrollment.Name;
        row.stage = enrollment.Stage__c;
        row.startDate = enrollment.Start_Date__c;
        row.endDate = enrollment.End_Date__c;
        if (enrollment.Contact__c != null) {
            row.personName = enrollment.Contact__r == null ? null : enrollment.Contact__r.Name;
        } else if (enrollment.Account__c != null) {
            row.personName = enrollment.Account__r == null ? null : enrollment.Account__r.Name;
        }
        return row;
    }

    private static List<Schema.PicklistEntry> stageEntries() {
        List<Schema.PicklistEntry> active = new List<Schema.PicklistEntry>();
        for (
            Schema.PicklistEntry entry : Enrollment__c.Stage__c.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                active.add(entry);
            }
        }
        return active;
    }

    /** A stage the picklist offers, or a refusal: the field is restricted anyway. */
    private static String checkedStage(String stage) {
        for (Schema.PicklistEntry entry : stageEntries()) {
            if (entry.getValue() == stage) {
                return entry.getValue();
            }
        }
        throw badRequest(Label.Programs_Roster_ActionFailed);
    }

    private static AuraHandledException badRequest(String message) {
        AuraHandledException refused = new AuraHandledException(message);
        refused.setMessage(message);
        return refused;
    }

    /**
     * A save a rule refused (a second open enrollment, a person the user may not see) is passed
     * on in its own words; anything else is logged first.
     */
    private static AuraHandledException report(Exception failure, Id recordId) {
        if (failure instanceof AuraHandledException) {
            return (AuraHandledException) failure;
        }
        if (failure instanceof DmlException) {
            return badRequest(((DmlException) failure).getDmlMessage(0));
        }
        ErrorLogger.log(failure, CONTEXT, recordId);
        return badRequest(Label.Programs_Roster_ActionFailed);
    }
}
