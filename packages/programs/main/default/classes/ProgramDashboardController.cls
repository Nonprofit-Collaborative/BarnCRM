/**
 * The Programs Dashboard tab (P-05, canonical model 29ZA "Program dashboard"): for a period, how
 * many programs are active, how many enrollments are open, new and completed, how many people were
 * served, how many services were delivered and how many deliveries were absences, in all and per
 * program. Read in user mode with aggregate queries, so each user counts only what they may see
 * (Participant Privacy, R-EN7). Returns plain wrappers (plan 9.9); the page computes the rates.
 */
public with sharing class ProgramDashboardController {
    private static final String CONTEXT = 'ProgramDashboardController';
    private static final String ACTIVE = 'Active';
    private static final String PRESENT = 'Present';
    private static final String COMPLETED = 'Completed';
    /** The table lists at most this many programs. */
    @TestVisible
    private static final Integer MAX_PROGRAMS = 200;

    /** The figures for the whole organization and for each program. */
    public class Dashboard {
        @AuraEnabled
        public Boolean canSee = false;
        @AuraEnabled
        public Integer activePrograms = 0;
        @AuraEnabled
        public Figures totals = new Figures();
        @AuraEnabled
        public List<ProgramFigures> programs = new List<ProgramFigures>();
        @AuraEnabled
        public Boolean moreThanShown = false;
    }

    /** One set of counts. */
    public virtual class Figures {
        @AuraEnabled
        public Integer openEnrollments = 0;
        @AuraEnabled
        public Integer newEnrollments = 0;
        @AuraEnabled
        public Integer completedEnrollments = 0;
        @AuraEnabled
        public Integer peopleServed = 0;
        @AuraEnabled
        public Integer delivered = 0;
        @AuraEnabled
        public Integer deliveries = 0;
    }

    /** The counts of one program. */
    public class ProgramFigures extends Figures {
        @AuraEnabled
        public Id programId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
    }

    /**
     * The figures for the period from `fromDate` to `toDate`, both included. Open enrollments and
     * active programs are counted as of now.
     */
    @AuraEnabled
    public static Dashboard getDashboard(Date fromDate, Date toDate) {
        Dashboard result = new Dashboard();
        if (
            fromDate == null ||
            toDate == null ||
            !Schema.SObjectType.Program__c.isAccessible() ||
            !Schema.SObjectType.Enrollment__c.isAccessible()
        ) {
            return result;
        }
        try {
            result.canSee = true;
            Map<Id, ProgramFigures> byProgram = new Map<Id, ProgramFigures>();
            countEnrollments(byProgram, fromDate, toDate);
            if (Schema.SObjectType.Service_Delivery__c.isAccessible()) {
                countDeliveries(byProgram, fromDate, toDate);
                result.totals.peopleServed = countPeople(byProgram, fromDate, toDate);
            }
            fillPrograms(result, byProgram);
            return result;
        } catch (Exception failure) {
            ErrorLogger.log(failure, CONTEXT, null);
            AuraHandledException refused = new AuraHandledException(
                Label.Programs_Dashboard_LoadFailed
            );
            refused.setMessage(Label.Programs_Dashboard_LoadFailed);
            throw refused;
        }
    }

    private static void countEnrollments(
        Map<Id, ProgramFigures> byProgram,
        Date fromDate,
        Date toDate
    ) {
        Set<String> open = EnrollmentService.OPEN_STAGES;
        for (AggregateResult row : [
            SELECT Program__c program, COUNT(Id) total
            FROM Enrollment__c
            WHERE Stage__c IN :open
            WITH USER_MODE
            GROUP BY Program__c
        ]) {
            figuresOf(byProgram, row).openEnrollments = count(row);
        }
        for (AggregateResult row : [
            SELECT Program__c program, COUNT(Id) total
            FROM Enrollment__c
            WHERE Start_Date__c >= :fromDate AND Start_Date__c <= :toDate
            WITH USER_MODE
            GROUP BY Program__c
        ]) {
            figuresOf(byProgram, row).newEnrollments = count(row);
        }
        for (AggregateResult row : [
            SELECT Program__c program, COUNT(Id) total
            FROM Enrollment__c
            WHERE Stage__c = :COMPLETED AND End_Date__c >= :fromDate AND End_Date__c <= :toDate
            WITH USER_MODE
            GROUP BY Program__c
        ]) {
            figuresOf(byProgram, row).completedEnrollments = count(row);
        }
    }

    private static void countDeliveries(
        Map<Id, ProgramFigures> byProgram,
        Date fromDate,
        Date toDate
    ) {
        for (AggregateResult row : [
            SELECT Service__r.Program__c program, Attendance__c attendance, COUNT(Id) total
            FROM Service_Delivery__c
            WHERE Delivery_Date__c >= :fromDate AND Delivery_Date__c <= :toDate
            WITH USER_MODE
            GROUP BY Service__r.Program__c, Attendance__c
        ]) {
            ProgramFigures figures = figuresOf(byProgram, row);
            figures.deliveries += count(row);
            if ((String) row.get('attendance') == PRESENT) {
                figures.delivered += count(row);
            }
        }
    }

    /**
     * Different people with a Present delivery in the period. A delivery names a contact or an
     * account, never both (R-SD1), so the two distinct counts add up. Returns the total across
     * programs, where one person served by two programs counts once.
     */
    private static Integer countPeople(
        Map<Id, ProgramFigures> byProgram,
        Date fromDate,
        Date toDate
    ) {
        for (AggregateResult row : [
            SELECT
                Service__r.Program__c program,
                COUNT_DISTINCT(Contact__c) contacts,
                COUNT_DISTINCT(Account__c) accounts
            FROM Service_Delivery__c
            WHERE
                Delivery_Date__c >= :fromDate
                AND Delivery_Date__c <= :toDate
                AND Attendance__c = :PRESENT
            WITH USER_MODE
            GROUP BY Service__r.Program__c
        ]) {
            figuresOf(byProgram, row).peopleServed =
                (Integer) row.get('contacts') + (Integer) row.get('accounts');
        }
        Integer people = 0;
        for (AggregateResult row : [
            SELECT COUNT_DISTINCT(Contact__c) contacts, COUNT_DISTINCT(Account__c) accounts
            FROM Service_Delivery__c
            WHERE
                Delivery_Date__c >= :fromDate
                AND Delivery_Date__c <= :toDate
                AND Attendance__c = :PRESENT
            WITH USER_MODE
        ]) {
            people += (Integer) row.get('contacts') + (Integer) row.get('accounts');
        }
        return people;
    }

    /** Every Active program and any other with activity, by name, with its counts and the totals. */
    private static void fillPrograms(Dashboard result, Map<Id, ProgramFigures> byProgram) {
        Set<Id> withActivity = byProgram.keySet();
        result.activePrograms = [
            SELECT COUNT()
            FROM Program__c
            WHERE Status__c = :ACTIVE
            WITH USER_MODE
        ];
        List<Program__c> programs = [
            SELECT Id, Name, Status__c
            FROM Program__c
            WHERE Status__c = :ACTIVE OR Id IN :withActivity
            WITH USER_MODE
            ORDER BY Name
            LIMIT :(MAX_PROGRAMS + 1)
        ];
        result.moreThanShown = programs.size() > MAX_PROGRAMS;
        for (Integer i = 0; i < programs.size() && i < MAX_PROGRAMS; i++) {
            Program__c program = programs[i];
            ProgramFigures figures = byProgram.containsKey(program.Id)
                ? byProgram.get(program.Id)
                : new ProgramFigures();
            figures.programId = program.Id;
            figures.name = program.Name;
            figures.status = program.Status__c;
            result.programs.add(figures);
        }
        for (ProgramFigures figures : byProgram.values()) {
            result.totals.openEnrollments += figures.openEnrollments;
            result.totals.newEnrollments += figures.newEnrollments;
            result.totals.completedEnrollments += figures.completedEnrollments;
            result.totals.delivered += figures.delivered;
            result.totals.deliveries += figures.deliveries;
        }
    }

    private static ProgramFigures figuresOf(
        Map<Id, ProgramFigures> byProgram,
        AggregateResult row
    ) {
        Id programId = (Id) row.get('program');
        if (!byProgram.containsKey(programId)) {
            byProgram.put(programId, new ProgramFigures());
        }
        return byProgram.get(programId);
    }

    private static Integer count(AggregateResult row) {
        return (Integer) row.get('total');
    }
}
