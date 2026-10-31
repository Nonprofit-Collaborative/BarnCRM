/**
 * Builds and removes the Programs sample data set (C-10, canonical model 29ZA "On a person,
 * Health Check and sample data"): three programs flagged `Sample_Data__c` (After-school
 * tutoring and Food pantry, Active; Summer reading, Completed), five services, and 18
 * enrollments of up to 12 of Core's sample people. Every record is saved in user mode through the
 * enrollment rules, as an administrator's would be.
 *
 * Removal deletes, one chunk per call: the sample people's enrollments in the sample programs,
 * then the sample programs no enrollment names any more (their services go with them). A sample
 * program one of the org's own people is enrolled in is kept, since its enrollment's lookup
 * refuses the delete, and `logWhatWasKept`, at the end, names each one in one Warning.
 */
public with sharing class ProgramSampleDataLoader {
    /** How many of Core's sample people take part. */
    @TestVisible
    private static final Integer PEOPLE = 12;

    /** Records deleted per removeNext() call. Tests lower it. */
    @TestVisible
    private static Integer removeChunkSize = 200;

    private static final String REMOVE_CONTEXT = 'ProgramsSampleData.RemoveStages';

    private static final String TUTORING = 'After-school tutoring';
    private static final String PANTRY = 'Food pantry';
    private static final String READING = 'Summer reading';

    // ------------------------------------------------------------------------- load

    /** The three programs and their services. */
    public static void loadPrograms() {
        Date today = Date.today();
        Program__c tutoring = program(
            TUTORING,
            'Active',
            'Students in grades 3 to 8 at our two partner schools.',
            today.addDays(-120),
            null
        );
        Program__c pantry = program(
            PANTRY,
            'Active',
            'Households in the county living on less than twice the poverty line.',
            today.addDays(-365),
            null
        );
        Program__c reading = program(
            READING,
            'Completed',
            'Children aged 6 to 11 over the summer break.',
            today.addDays(-150),
            today.addDays(-90)
        );
        List<Program__c> programs = new List<Program__c>{ tutoring, pantry, reading };
        Database.insert(programs, AccessLevel.USER_MODE);

        Database.insert(
            new List<Service__c>{
                service(tutoring.Id, 'Tutoring hour', 'hours'),
                service(tutoring.Id, 'Homework club session', 'sessions'),
                service(pantry.Id, 'Grocery bag', 'bags'),
                service(pantry.Id, 'Hot meal', 'meals'),
                service(reading.Id, 'Reading circle', 'sessions')
            },
            AccessLevel.USER_MODE
        );
    }

    /**
     * The enrollments: six in tutoring (four Enrolled, one Applied, one Withdrawn), eight
     * Enrolled in the pantry, four Completed in summer reading. Nothing when there are no sample
     * people or programs.
     */
    public static void loadEnrollments() {
        List<Contact> people = [
            SELECT Id
            FROM Contact
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
            ORDER BY Sample_Data_Key__c NULLS LAST, Id
            LIMIT :PEOPLE
        ];
        Map<String, Program__c> programs = new Map<String, Program__c>();
        for (Program__c program : samplePrograms()) {
            programs.put(program.Name, program);
        }
        if (people.isEmpty() || programs.size() < 3) {
            return;
        }
        Integer count = people.size();
        Date today = Date.today();
        List<Enrollment__c> enrollments = new List<Enrollment__c>();
        Program__c tutoring = programs.get(TUTORING);
        for (Integer i = 0; i < 6; i++) {
            Enrollment__c row = enrollment(tutoring.Id, people[Math.mod(i, count)].Id);
            if (i == 4) {
                row.Stage__c = EnrollmentService.STAGE_APPLIED;
            } else if (i == 5) {
                row.Stage__c = EnrollmentService.STAGE_WITHDRAWN;
                row.Start_Date__c = today.addDays(-100);
                row.End_Date__c = today.addDays(-30);
            } else {
                row.Start_Date__c = today.addDays(-110 + 7 * i);
            }
            enrollments.add(row);
        }
        Program__c pantry = programs.get(PANTRY);
        for (Integer i = 4; i < 12; i++) {
            Enrollment__c row = enrollment(pantry.Id, people[Math.mod(i, count)].Id);
            row.Start_Date__c = today.addDays(-300 + 20 * i);
            enrollments.add(row);
        }
        Program__c reading = programs.get(READING);
        for (Integer i = 0; i < 4; i++) {
            Enrollment__c row = enrollment(reading.Id, people[Math.mod(i, count)].Id);
            row.Stage__c = EnrollmentService.STAGE_COMPLETED;
            row.Start_Date__c = reading.Start_Date__c;
            row.End_Date__c = reading.End_Date__c;
            enrollments.add(row);
        }
        // With fewer sample people than the set asks for, a person may repeat in a program:
        // keep one open enrollment per person per program (R-EN2).
        Database.insert(dropRepeats(enrollments), AccessLevel.USER_MODE);
    }

    /**
     * The service deliveries (P-02): a grocery bag a week for the last four weeks to each person
     * Enrolled in the pantry, one of them missed, and two tutoring sessions of two hours to each
     * person Enrolled in tutoring. Linked to their enrollments by the delivery rules (R-SD3).
     */
    public static void loadDeliveries() {
        Map<String, Id> serviceIds = new Map<String, Id>();
        for (Service__c service : [
            SELECT Id, Name
            FROM Service__c
            WHERE Program__r.Sample_Data__c = TRUE
            WITH USER_MODE
        ]) {
            serviceIds.put(service.Name, service.Id);
        }
        Date today = Date.today();
        List<Service_Delivery__c> deliveries = new List<Service_Delivery__c>();
        Integer pantryPeople = 0;
        for (Enrollment__c enrollment : [
            SELECT Contact__c, Program__r.Name
            FROM Enrollment__c
            WHERE
                Program__r.Sample_Data__c = TRUE
                AND Stage__c = :EnrollmentService.STAGE_ENROLLED
                AND Contact__r.Sample_Data__c = TRUE
            WITH USER_MODE
            ORDER BY Program__r.Name, Name
        ]) {
            Boolean pantry = enrollment.Program__r.Name == PANTRY;
            Id serviceId = serviceIds.get(pantry ? 'Grocery bag' : 'Tutoring hour');
            if (serviceId == null) {
                continue;
            }
            Integer weeks = pantry ? 4 : 2;
            for (Integer week = 0; week < weeks; week++) {
                Service_Delivery__c delivery = new Service_Delivery__c(
                    Service__c = serviceId,
                    Contact__c = enrollment.Contact__c,
                    Delivery_Date__c = today.addDays(-7 * week),
                    Quantity__c = pantry ? 1 : 2
                );
                if (pantry && pantryPeople == 3 && week == 1) {
                    delivery.Attendance__c = ServiceDeliveryService.UNEXCUSED_ABSENCE;
                }
                deliveries.add(delivery);
            }
            if (pantry) {
                pantryPeople++;
            }
        }
        Database.insert(deliveries, AccessLevel.USER_MODE);
    }

    // ------------------------------------------------------------------------- status card

    /** The sample people's enrollments in sample programs. */
    public static Integer countSampleEnrollments() {
        return [
            SELECT COUNT()
            FROM Enrollment__c
            WHERE Program__r.Sample_Data__c = TRUE AND Contact__r.Sample_Data__c = TRUE
            WITH USER_MODE
        ];
    }

    /** True while any sample program is in the org. */
    public static Boolean hasSamplePrograms() {
        return [SELECT COUNT() FROM Program__c WHERE Sample_Data__c = TRUE WITH USER_MODE LIMIT 1] >
            0;
    }

    // ------------------------------------------------------------------------- removal

    /** How many removeNext() calls clear every Programs sample record. */
    public static Integer removeStageCount() {
        Integer stages = 0;
        for (
            Integer recordCount : new List<Integer>{
                [
                    SELECT COUNT()
                    FROM Service_Delivery__c
                    WHERE
                        Service__r.Program__r.Sample_Data__c = TRUE
                        AND Contact__r.Sample_Data__c = TRUE
                    WITH USER_MODE
                ],
                countSampleEnrollments(),
                [SELECT COUNT() FROM Program__c WHERE Sample_Data__c = TRUE WITH USER_MODE]
            }
        ) {
            stages += (recordCount + removeChunkSize - 1) / removeChunkSize;
        }
        return stages;
    }

    /**
     * Deletes the next chunk of Programs sample records and returns how many went, 0 once none
     * are left: the service deliveries first, then the enrollments, then the programs no
     * enrollment or delivery is left on.
     */
    public static Integer removeNext() {
        List<Service_Delivery__c> deliveries = [
            SELECT Id
            FROM Service_Delivery__c
            WHERE Service__r.Program__r.Sample_Data__c = TRUE AND Contact__r.Sample_Data__c = TRUE
            WITH USER_MODE
            LIMIT :removeChunkSize
        ];
        if (!deliveries.isEmpty()) {
            Database.delete(deliveries, AccessLevel.USER_MODE);
            return deliveries.size();
        }
        List<Enrollment__c> enrollments = [
            SELECT Id
            FROM Enrollment__c
            WHERE Program__r.Sample_Data__c = TRUE AND Contact__r.Sample_Data__c = TRUE
            WITH USER_MODE
            LIMIT :removeChunkSize
        ];
        if (!enrollments.isEmpty()) {
            Database.delete(enrollments, AccessLevel.USER_MODE);
            return enrollments.size();
        }
        // A program a real person's delivery is on stays: the delivery's lookup refuses it.
        Set<Id> inUse = new Set<Id>();
        for (AggregateResult row : [
            SELECT Service__r.Program__c program
            FROM Service_Delivery__c
            WHERE Service__r.Program__r.Sample_Data__c = TRUE
            WITH USER_MODE
            GROUP BY Service__r.Program__c
        ]) {
            inUse.add((Id) row.get('program'));
        }
        List<Program__c> programs = [
            SELECT Id
            FROM Program__c
            WHERE
                Sample_Data__c = TRUE
                AND Id NOT IN (SELECT Program__c FROM Enrollment__c)
                AND Id NOT IN :inUse
            WITH USER_MODE
            LIMIT :removeChunkSize
        ];
        if (!programs.isEmpty()) {
            Database.delete(programs, AccessLevel.USER_MODE);
        }
        return programs.size();
    }

    /**
     * Logs one Warning naming each sample program real enrollments kept, and returns its message;
     * null when nothing was kept. Run once, after the last stage.
     */
    public static String logWhatWasKept() {
        List<String> names = new List<String>();
        for (Program__c program : samplePrograms()) {
            names.add(program.Name);
        }
        if (names.isEmpty()) {
            return null;
        }
        String message = String.format(
            Label.Programs_SampleData_Kept,
            new List<Object>{ String.join(names, ', ') }
        );
        ErrorLogger.logMessage(message, REMOVE_CONTEXT, ErrorLogger.SEVERITY_WARNING);
        return message;
    }

    // ------------------------------------------------------------------------- helpers

    private static List<Program__c> samplePrograms() {
        return [
            SELECT Id, Name, Start_Date__c, End_Date__c
            FROM Program__c
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
            ORDER BY Name
        ];
    }

    private static List<Enrollment__c> dropRepeats(List<Enrollment__c> enrollments) {
        Set<String> openKeys = new Set<String>();
        List<Enrollment__c> kept = new List<Enrollment__c>();
        for (Enrollment__c row : enrollments) {
            String key = row.Program__c + ':' + row.Contact__c;
            if (EnrollmentService.isOpen(row.Stage__c) && !openKeys.add(key)) {
                continue;
            }
            kept.add(row);
        }
        return kept;
    }

    private static Program__c program(
        String name,
        String status,
        String targetPopulation,
        Date startDate,
        Date endDate
    ) {
        return new Program__c(
            Name = name,
            Status__c = status,
            Target_Population__c = targetPopulation,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Sample_Data__c = true
        );
    }

    private static Service__c service(Id programId, String name, String unit) {
        return new Service__c(Program__c = programId, Name = name, Unit_Of_Measure__c = unit);
    }

    private static Enrollment__c enrollment(Id programId, Id contactId) {
        return new Enrollment__c(
            Program__c = programId,
            Contact__c = contactId,
            Stage__c = EnrollmentService.STAGE_ENROLLED
        );
    }
}
