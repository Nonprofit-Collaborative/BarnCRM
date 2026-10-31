/**
 * The Service Delivery Log panel's server side (canonical model 29ZB): the log for a service and
 * day, saving new and changed deliveries through the delivery rules, and refusals passed on in
 * their own words.
 */
@IsTest(
    testFor='ApexClass:ServiceDeliveryLogController, ApexClass:ServiceDeliverySelector, ApexClass:ServiceDeliveryIntegrity'
)
private class ServiceDeliveryLogControllerTest {
    private static final String ADMIN = 'Programs_Admin';

    private static final List<String> STAFF = new List<String>{ 'BarnCRM_Staff', 'Programs_Staff' };

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith('Writer', STAFF);
        TestUsers.standardUserWith('Colleague', STAFF);
        TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        );
    }

    private static void contactMode() {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
    }

    private static Contact person(String lastName) {
        Contact record = HouseholdTestDataFactory.newContact('Pat', lastName);
        insert record;
        return record;
    }

    private static Service__c serviceIn(Program__c program, String name) {
        Service__c service = new Service__c(
            Program__c = program.Id,
            Name = name,
            Unit_Of_Measure__c = 'hours'
        );
        insert service;
        return service;
    }

    private static ServiceDeliveryLogController.Row rowOf(
        ServiceDeliveryLogController.Log log,
        Id person
    ) {
        for (ServiceDeliveryLogController.Row row : log.rows) {
            if (row.key == person) {
                return row;
            }
        }
        return null;
    }

    private static ServiceDeliveryLogController.Entry entryFor(
        ServiceDeliveryLogController.Row row,
        String attendance,
        Decimal quantity
    ) {
        ServiceDeliveryLogController.Entry entry = new ServiceDeliveryLogController.Entry();
        entry.contactId = row.contactId;
        entry.accountId = row.accountId;
        entry.enrollmentId = row.enrollmentId;
        entry.deliveryId = row.deliveryId;
        entry.attendance = attendance;
        entry.quantity = quantity;
        return entry;
    }

    @IsTest
    static void listsTheOpenEnrollmentsForTheFirstServiceToday() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c tutoring = new Program__c(Name = 'Tutoring');
            insert tutoring;
            Service__c homework = serviceIn(tutoring, 'Homework club');
            serviceIn(tutoring, 'Tutoring hour');
            Contact ana = person('Rivera');
            Contact ben = person('Okafor');
            insert new List<Enrollment__c>{
                new Enrollment__c(Program__c = tutoring.Id, Contact__c = ana.Id),
                new Enrollment__c(
                    Program__c = tutoring.Id,
                    Contact__c = ben.Id,
                    Stage__c = 'Completed'
                )
            };

            Test.startTest();
            ServiceDeliveryLogController.Log log = ServiceDeliveryLogController.getLog(
                tutoring.Id,
                null,
                null
            );
            Test.stopTest();

            Assert.areEqual(2, log.services.size(), 'Both active services are offered.');
            Assert.areEqual(homework.Id, log.serviceId, 'The first by name is chosen.');
            Assert.areEqual('hours', log.services[0].unit, 'With its unit.');
            Assert.areEqual(Date.today(), log.deliveryDate, 'Today by default.');
            Assert.areEqual(3, log.attendance.size(), 'Every attendance value.');
            Assert.isTrue(log.canEdit, 'An admin can record.');
            Assert.areEqual(1, log.rows.size(), 'Only the open enrollment is listed.');
            Assert.areEqual('Pat Rivera', log.rows[0].personName, 'By the person name.');
            Assert.isNull(log.rows[0].deliveryId, 'Nothing recorded yet.');
        }
    }

    @IsTest
    static void savesNewAndChangedDeliveries() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c tutoring = new Program__c(Name = 'Tutoring');
            insert tutoring;
            Service__c hour = serviceIn(tutoring, 'Tutoring hour');
            Contact ana = person('Rivera');
            Contact ben = person('Okafor');
            insert new List<Enrollment__c>{
                new Enrollment__c(Program__c = tutoring.Id, Contact__c = ana.Id),
                new Enrollment__c(Program__c = tutoring.Id, Contact__c = ben.Id)
            };
            Date day = Date.today().addDays(-1);
            ServiceDeliveryLogController.Log log = ServiceDeliveryLogController.getLog(
                tutoring.Id,
                hour.Id,
                day
            );

            Test.startTest();
            ServiceDeliveryLogController.Log first = ServiceDeliveryLogController.save(
                tutoring.Id,
                hour.Id,
                day,
                new List<ServiceDeliveryLogController.Entry>{
                    entryFor(rowOf(log, ana.Id), 'Present', 2),
                    entryFor(rowOf(log, ben.Id), 'Present', null),
                    entryFor(rowOf(log, ben.Id), '', null)
                }
            );
            ServiceDeliveryLogController.Log second = ServiceDeliveryLogController.save(
                tutoring.Id,
                hour.Id,
                day,
                new List<ServiceDeliveryLogController.Entry>{
                    entryFor(rowOf(first, ben.Id), 'Excused Absence', 5)
                }
            );
            Test.stopTest();

            Assert.areEqual(2, first.saved, 'Two recorded; the blank one is skipped.');
            Assert.areEqual(2, rowOf(first, ana.Id).quantity, 'Ana got two hours.');
            Assert.areEqual(1, rowOf(first, ben.Id).quantity, 'A blank quantity counts one.');
            Assert.isNotNull(rowOf(first, ana.Id).deliveryId, 'Ana now has a delivery.');
            Assert.areEqual(1, second.saved, 'One changed.');
            Assert.areEqual('Excused Absence', rowOf(second, ben.Id).attendance, 'Ben was absent.');
            Assert.areEqual(0, rowOf(second, ben.Id).quantity, 'An absence delivers nothing.');
            Service_Delivery__c saved = [
                SELECT Enrollment__c, Delivery_Date__c
                FROM Service_Delivery__c
                WHERE Contact__c = :ana.Id
            ];
            Assert.areEqual(day, saved.Delivery_Date__c, 'On the day chosen.');
            Assert.areEqual(rowOf(log, ana.Id).enrollmentId, saved.Enrollment__c, 'Linked.');
        }
    }

    @IsTest
    static void aDeliveryTheUserCannotSeeIsChangedNotDoubled() {
        Program__c pantry = new Program__c(Name = 'Pantry');
        Service__c meal;
        Contact ana;
        Enrollment__c enrolled;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            insert pantry;
            meal = serviceIn(pantry, 'Meal');
        }
        Date day = Date.today();
        System.runAs(TestUsers.standardUserWith('Writer', STAFF)) {
            ana = person('Rivera');
            enrolled = new Enrollment__c(Program__c = pantry.Id, Contact__c = ana.Id);
            insert enrolled;
            insert new Service_Delivery__c(
                Service__c = meal.Id,
                Contact__c = ana.Id,
                Enrollment__c = enrolled.Id,
                Delivery_Date__c = day,
                Attendance__c = 'Present',
                Quantity__c = 1
            );
        }
        // As under the Private preset: the colleague cannot see the writer's delivery.
        delete [
            SELECT Id
            FROM Service_Delivery__Share
            WHERE RowCause = :Schema.Service_Delivery__Share.RowCause.Programs_Participants__c
        ];
        ServiceDeliveryLogController.Entry entry = new ServiceDeliveryLogController.Entry();
        entry.contactId = ana.Id;
        entry.enrollmentId = enrolled.Id;
        entry.attendance = 'Present';
        entry.quantity = 3;

        Test.startTest();
        ServiceDeliveryLogController.Log after;
        Integer seen;
        System.runAs(TestUsers.standardUserWith('Colleague', STAFF)) {
            seen = [SELECT COUNT() FROM Service_Delivery__c WITH USER_MODE];
            after = ServiceDeliveryLogController.save(
                pantry.Id,
                meal.Id,
                day,
                new List<ServiceDeliveryLogController.Entry>{ entry }
            );
        }
        Test.stopTest();

        Assert.areEqual(0, seen, 'The colleague cannot see the delivery.');
        List<Service_Delivery__c> rows = [
            SELECT Quantity__c
            FROM Service_Delivery__c
            WHERE Contact__c = :ana.Id
        ];
        Assert.areEqual(1, rows.size(), 'R-SD4: one row per person, service and day.');
        Assert.areEqual(3, rows[0].Quantity__c, 'The existing row was changed.');
        Assert.areEqual(1, after.saved, 'One saved.');
        ServiceDeliveryLogController.Row row = rowOf(after, ana.Id);
        Assert.isTrue(
            row == null || row.deliveryId == null,
            'The hidden row is still not shown to the colleague.'
        );
    }

    @IsTest
    static void showsSomeoneRecordedWithoutAnOpenEnrollment() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c pantry = new Program__c(Name = 'Pantry');
            insert pantry;
            Service__c bag = serviceIn(pantry, 'Grocery bag');
            Contact cal = person('Nguyen');
            insert new Service_Delivery__c(Service__c = bag.Id, Contact__c = cal.Id);

            Test.startTest();
            ServiceDeliveryLogController.Log log = ServiceDeliveryLogController.getLog(
                pantry.Id,
                bag.Id,
                Date.today()
            );
            Test.stopTest();

            Assert.areEqual(1, log.rows.size(), 'The walk-in is shown.');
            Assert.areEqual('Pat Nguyen', log.rows[0].personName, 'By name.');
            Assert.isNotNull(log.rows[0].deliveryId, 'With the delivery.');
        }
    }

    @IsTest
    static void aProgramWithoutServicesHasNoRows() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Program__c empty = new Program__c(Name = 'Empty');
            insert empty;

            Test.startTest();
            ServiceDeliveryLogController.Log log = ServiceDeliveryLogController.getLog(
                empty.Id,
                null,
                null
            );
            Test.stopTest();

            Assert.isNull(log.serviceId, 'No service.');
            Assert.areEqual(0, log.rows.size(), 'No rows.');
        }
    }

    @IsTest
    static void aReaderCannotRecord() {
        Program__c tutoring = new Program__c(Name = 'Tutoring');
        System.runAs(TestUsers.adminWith(ADMIN)) {
            insert tutoring;
        }
        System.runAs(TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        )) {
            Test.startTest();
            ServiceDeliveryLogController.Log log = ServiceDeliveryLogController.getLog(
                tutoring.Id,
                null,
                null
            );
            Test.stopTest();

            Assert.isFalse(log.canEdit, 'Read only.');
        }
    }

    @IsTest
    static void refusesBadRequestsInTheirOwnWords() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c tutoring = new Program__c(Name = 'Tutoring');
            insert tutoring;
            Service__c hour = serviceIn(tutoring, 'Tutoring hour');
            Contact ana = person('Rivera');
            ServiceDeliveryLogController.Entry unknown = new ServiceDeliveryLogController.Entry();
            unknown.contactId = ana.Id;
            unknown.attendance = 'Late';
            ServiceDeliveryLogController.Entry negative = new ServiceDeliveryLogController.Entry();
            negative.contactId = ana.Id;
            negative.attendance = 'Present';
            negative.quantity = -1;

            Test.startTest();
            List<String> messages = new List<String>();
            for (
                List<ServiceDeliveryLogController.Entry> entries : new List<List<ServiceDeliveryLogController.Entry>>{
                    new List<ServiceDeliveryLogController.Entry>{ unknown },
                    new List<ServiceDeliveryLogController.Entry>{ negative }
                }
            ) {
                try {
                    ServiceDeliveryLogController.save(tutoring.Id, hour.Id, Date.today(), entries);
                    messages.add(null);
                } catch (AuraHandledException refused) {
                    messages.add(refused.getMessage());
                }
            }
            try {
                ServiceDeliveryLogController.getLog(null, null, null);
                messages.add(null);
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
            try {
                ServiceDeliveryLogController.save(tutoring.Id, null, null, null);
                messages.add(null);
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
            Test.stopTest();

            Assert.areEqual(Label.Programs_Log_ActionFailed, messages[0], 'Unknown attendance.');
            Assert.isNotNull(messages[1], 'A negative quantity is refused.');
            Assert.areNotEqual(
                Label.Programs_Log_ActionFailed,
                messages[1],
                'In the rule own words.'
            );
            Assert.areEqual(Label.Programs_Log_ActionFailed, messages[2], 'No program.');
            Assert.areEqual(Label.Programs_Log_ActionFailed, messages[3], 'No service or day.');
            Assert.areEqual(0, [SELECT COUNT() FROM Service_Delivery__c], 'Nothing was saved.');
        }
    }
}
