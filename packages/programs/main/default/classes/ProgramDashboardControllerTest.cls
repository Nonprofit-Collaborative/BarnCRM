/**
 * The Programs Dashboard (P-05, canonical model 29ZA "Program dashboard"): open, new and completed
 * enrollments, people served, services delivered and absences, in all and per program, for the
 * period asked; every Active program listed, others only with activity; nothing for a user without
 * Programs.
 */
@IsTest(testFor='ApexClass:ProgramDashboardController')
private class ProgramDashboardControllerTest {
    private static final String ADMIN = 'Programs_Admin';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith('Noprograms', new List<String>{ 'BarnCRM_Read_Only' });
    }

    private static List<Contact> people(Integer howMany) {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
        List<Contact> records = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            records.add(HouseholdTestDataFactory.newContact('Person' + i, 'Dashboard'));
        }
        insert records;
        return records;
    }

    private static Service_Delivery__c delivery(
        Id serviceId,
        Id contactId,
        Date day,
        String attendance
    ) {
        return new Service_Delivery__c(
            Service__c = serviceId,
            Contact__c = contactId,
            Delivery_Date__c = day,
            Attendance__c = attendance,
            Quantity__c = attendance == 'Present' ? 1 : 0
        );
    }

    @IsTest
    static void countsThePeriodInAllAndPerProgram() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            List<Contact> folks = people(3);
            Date today = Date.today();
            Date monthStart = today.toStartOfMonth();
            Program__c pantry = new Program__c(Name = 'Pantry', Status__c = 'Active');
            Program__c tutoring = new Program__c(Name = 'Tutoring', Status__c = 'Active');
            Program__c oldCamp = new Program__c(Name = 'Old Camp', Status__c = 'Completed');
            Program__c idle = new Program__c(Name = 'Idle', Status__c = 'Completed');
            insert new List<Program__c>{ pantry, tutoring, oldCamp, idle };
            Service__c meal = new Service__c(Name = 'Meal', Program__c = pantry.Id);
            Service__c camp = new Service__c(Name = 'Day', Program__c = oldCamp.Id);
            insert new List<Service__c>{ meal, camp };
            insert new List<Enrollment__c>{
                new Enrollment__c(
                    Program__c = pantry.Id,
                    Contact__c = folks[0].Id,
                    Start_Date__c = monthStart
                ),
                new Enrollment__c(
                    Program__c = pantry.Id,
                    Contact__c = folks[1].Id,
                    Start_Date__c = monthStart.addMonths(-3)
                ),
                new Enrollment__c(
                    Program__c = oldCamp.Id,
                    Contact__c = folks[2].Id,
                    Stage__c = 'Completed',
                    Start_Date__c = monthStart.addMonths(-6),
                    End_Date__c = monthStart
                )
            };
            insert new List<Service_Delivery__c>{
                delivery(meal.Id, folks[0].Id, monthStart, 'Present'),
                delivery(meal.Id, folks[0].Id, monthStart, 'Present'),
                delivery(meal.Id, folks[1].Id, monthStart, 'Excused Absence'),
                delivery(meal.Id, folks[1].Id, monthStart.addMonths(-2), 'Present'),
                delivery(camp.Id, folks[0].Id, monthStart, 'Present')
            };

            Test.startTest();
            ProgramDashboardController.Dashboard result = ProgramDashboardController.getDashboard(
                monthStart,
                monthStart.addMonths(1).addDays(-1)
            );
            Test.stopTest();

            Assert.isTrue(result.canSee, 'An admin sees the dashboard.');
            Assert.areEqual(2, result.activePrograms, 'Two Active programs.');
            Assert.areEqual(2, result.totals.openEnrollments, 'Two open now.');
            Assert.areEqual(1, result.totals.newEnrollments, 'One started this month.');
            Assert.areEqual(1, result.totals.completedEnrollments, 'One completed this month.');
            Assert.areEqual(3, result.totals.delivered, 'Three Present this month.');
            Assert.areEqual(4, result.totals.deliveries, 'Four this month, absence included.');
            Assert.areEqual(1, result.totals.peopleServed, 'One person, served by two programs.');

            List<String> names = new List<String>();
            for (ProgramDashboardController.ProgramFigures each : result.programs) {
                names.add(each.name);
            }
            Assert.areEqual(
                new List<String>{ 'Old Camp', 'Pantry', 'Tutoring' },
                names,
                'Active programs and those with activity, by name; Idle is left out.'
            );
            ProgramDashboardController.ProgramFigures food = result.programs[1];
            Assert.areEqual(2, food.openEnrollments, 'Pantry: two open.');
            Assert.areEqual(1, food.newEnrollments, 'Pantry: one new.');
            Assert.areEqual(2, food.delivered, 'Pantry: two Present.');
            Assert.areEqual(3, food.deliveries, 'Pantry: three in all.');
            Assert.areEqual(1, food.peopleServed, 'Pantry: one person served.');
            Assert.areEqual(0, result.programs[2].deliveries, 'Tutoring: nothing yet.');
            Assert.isFalse(result.moreThanShown, 'Nothing left out.');
        }
    }

    @IsTest
    static void aUserWithoutProgramsOrWithoutAPeriodGetsNothing() {
        ProgramDashboardController.Dashboard withoutPrograms;
        System.runAs(TestUsers.standardUserWith(
            'Noprograms',
            new List<String>{ 'BarnCRM_Read_Only' }
        )) {
            Test.startTest();
            withoutPrograms = ProgramDashboardController.getDashboard(Date.today(), Date.today());
            Test.stopTest();
        }
        ProgramDashboardController.Dashboard withoutPeriod;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            withoutPeriod = ProgramDashboardController.getDashboard(null, Date.today());
        }

        Assert.isFalse(withoutPrograms.canSee, 'No Programs set, no dashboard.');
        Assert.isFalse(withoutPeriod.canSee, 'No period, nothing counted.');
    }
}
