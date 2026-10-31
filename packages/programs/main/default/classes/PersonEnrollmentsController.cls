/**
 * The Programs card on a person (P-01): every enrollment the person has, open ones first, with
 * its program, stage and dates. Read only; enrolling and changing a stage happen on the program.
 *
 * Read in user mode, so the card shows only what the user may see. A user who cannot read
 * enrollments gets `canSee` false and no card; so does an account that is a household or an
 * organization rather than a person. On a person account the card lists the enrollments naming
 * the account or its one contact, so it never names a person account field.
 */
public with sharing class PersonEnrollmentsController {
    /** The card lists at most this many; the Enrollments tab lists them all. */
    @TestVisible
    private static final Integer MAX_SHOWN = 200;

    /** What the card shows. */
    public class PersonEnrollments {
        @AuraEnabled
        public Boolean canSee = false;
        @AuraEnabled
        public List<Row> enrollments = new List<Row>();
        @AuraEnabled
        public Boolean moreThanShown = false;
        /** The latest Delivery Date of a Present delivery to the person (P-05), or null. */
        @AuraEnabled
        public Date lastServiceDate;
        /** How many Present deliveries the person has, of those the user can see (P-05). */
        @AuraEnabled
        public Integer servicesAttended = 0;
    }

    /** One enrollment of the person. */
    public class Row {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public Id programId;
        @AuraEnabled
        public String programName;
        @AuraEnabled
        public String stage;
        @AuraEnabled
        public String stageLabel;
        @AuraEnabled
        public Boolean isOpen = false;
        @AuraEnabled
        public Date startDate;
        @AuraEnabled
        public Date endDate;
    }

    @AuraEnabled(cacheable=true)
    public static PersonEnrollments getEnrollments(Id personId) {
        PersonEnrollments result = new PersonEnrollments();
        if (personId == null || !Schema.SObjectType.Enrollment__c.isAccessible()) {
            return result;
        }
        try {
            if (failForTest) {
                throw new QueryException('Simulated failure.');
            }
            return read(result, personId);
        } catch (Exception failure) {
            // Anything unexpected is in the Error Log before the card says it could not load.
            ErrorLogger.log(failure, CONTEXT, personId);
            AuraHandledException refused = new AuraHandledException(
                Label.Programs_PersonEnrollments_LoadFailed
            );
            refused.setMessage(Label.Programs_PersonEnrollments_LoadFailed);
            throw refused;
        }
    }

    private static final String CONTEXT = 'PersonEnrollmentsController';

    /** Set by a test to prove a failure is logged and reported in the card's own words. */
    @TestVisible
    private static Boolean failForTest = false;

    private static PersonEnrollments read(PersonEnrollments result, Id personId) {
        Set<Id> contactIds = new Set<Id>();
        Id accountId;
        Schema.SObjectType type = personId.getSObjectType();
        if (type == Contact.SObjectType) {
            contactIds.add(personId);
        } else if (type == Account.SObjectType && isPersonAccount(personId)) {
            accountId = personId;
            contactIds.addAll(EnrollmentSelector.selectContactIdsOf(personId));
        } else {
            return result;
        }
        result.canSee = true;

        Map<String, String> stageLabels = stageLabels();
        List<Row> open = new List<Row>();
        List<Row> ended = new List<Row>();
        List<Enrollment__c> found = EnrollmentSelector.selectForPerson(
            contactIds,
            accountId,
            MAX_SHOWN + 1
        );
        result.moreThanShown = found.size() > MAX_SHOWN;
        for (Integer i = 0; i < found.size() && i < MAX_SHOWN; i++) {
            Row row = toRow(found[i], stageLabels);
            (row.isOpen ? open : ended).add(row);
        }
        result.enrollments.addAll(open);
        result.enrollments.addAll(ended);
        fillLastService(result, contactIds, accountId);
        return result;
    }

    /** The person's last service and how many they attended, in user mode (P-05). */
    private static void fillLastService(
        PersonEnrollments result,
        Set<Id> contactIds,
        Id accountId
    ) {
        if (!Schema.SObjectType.Service_Delivery__c.isAccessible()) {
            return;
        }
        for (AggregateResult row : [
            SELECT MAX(Delivery_Date__c) lastDate, COUNT(Id) total
            FROM Service_Delivery__c
            WHERE
                Attendance__c = 'Present'
                AND (Contact__c IN :contactIds
                OR (Account__c != NULL
                AND Account__c = :accountId))
            WITH USER_MODE
        ]) {
            result.lastServiceDate = (Date) row.get('lastDate');
            result.servicesAttended = (Integer) row.get('total');
        }
    }

    private static Row toRow(Enrollment__c enrollment, Map<String, String> stageLabels) {
        Row row = new Row();
        row.recordId = enrollment.Id;
        row.programId = enrollment.Program__c;
        row.programName = enrollment.Program__r?.Name;
        row.stage = enrollment.Stage__c;
        row.stageLabel = stageLabels.containsKey(enrollment.Stage__c)
            ? stageLabels.get(enrollment.Stage__c)
            : enrollment.Stage__c;
        row.isOpen = EnrollmentService.isOpen(enrollment.Stage__c);
        row.startDate = enrollment.Start_Date__c;
        row.endDate = enrollment.End_Date__c;
        return row;
    }

    /**
     * An account is a person only where the org has person accounts and its record type is a
     * person type, read without naming any person account field.
     */
    private static Boolean isPersonAccount(Id accountId) {
        if (!OrgShapeDetector.hasPersonAccounts()) {
            return false;
        }
        List<Account> found = [
            SELECT RecordTypeId
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        return !found.isEmpty() &&
            OrgShapeDetector.personAccountRecordTypeIds().contains(found[0].RecordTypeId);
    }

    private static Map<String, String> stageLabels() {
        Map<String, String> byValue = new Map<String, String>();
        for (
            Schema.PicklistEntry entry : Enrollment__c.Stage__c.getDescribe().getPicklistValues()
        ) {
            byValue.put(entry.getValue(), entry.getLabel());
        }
        return byValue;
    }
}
