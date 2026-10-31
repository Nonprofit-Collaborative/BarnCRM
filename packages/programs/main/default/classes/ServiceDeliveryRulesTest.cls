/**
 * Service delivery rules (canonical model 29ZB): an absence delivers nothing (R-SD2), the
 * enrollment fills itself in (R-SD3), one person per delivery (R-SD1), a negative quantity and a
 * service with deliveries are refused.
 */
@IsTest(
    testFor='ApexClass:ServiceDeliveryRulesHandler, ApexClass:ServiceDeliveryService, ApexClass:ServiceDeliverySelector'
)
private class ServiceDeliveryRulesTest {
    private static final String ADMIN = 'Programs_Admin';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
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

    private static Service__c serviceIn(Program__c program) {
        Service__c service = new Service__c(
            Program__c = program.Id,
            Name = 'Hot meal',
            Unit_Of_Measure__c = 'meals'
        );
        insert service;
        return service;
    }

    private static Service_Delivery__c saved(Id deliveryId) {
        return [
            SELECT Quantity__c, Enrollment__c, Attendance__c, Delivery_Date__c
            FROM Service_Delivery__c
            WHERE Id = :deliveryId
        ];
    }

    @IsTest
    static void anAbsenceDeliversNothingAndDefaultsHold() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c pantry = new Program__c(Name = 'Pantry');
            insert pantry;
            Service__c meal = serviceIn(pantry);
            Contact ana = person('Rivera');
            Service_Delivery__c present = new Service_Delivery__c(
                Service__c = meal.Id,
                Contact__c = ana.Id
            );
            Service_Delivery__c absent = new Service_Delivery__c(
                Service__c = meal.Id,
                Contact__c = ana.Id,
                Attendance__c = ServiceDeliveryService.UNEXCUSED_ABSENCE,
                Quantity__c = 3
            );

            Test.startTest();
            insert new List<Service_Delivery__c>{ present, absent };
            Test.stopTest();

            Service_Delivery__c came = saved(present.Id);
            Assert.areEqual(1, came.Quantity__c, 'One, by default.');
            Assert.areEqual('Present', came.Attendance__c, 'Present, by default.');
            Assert.areEqual(Date.today(), came.Delivery_Date__c, 'Today, by default.');
            Assert.areEqual(0, saved(absent.Id).Quantity__c, 'An absence delivers nothing.');
        }
    }

    @IsTest
    static void theOpenEnrollmentIsLinkedElseTheLatestElseNone() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c pantry = new Program__c(Name = 'Pantry');
            insert pantry;
            Service__c meal = serviceIn(pantry);
            Contact ana = person('Rivera');
            Contact ben = person('Okafor');
            Contact cal = person('Nobody');
            Enrollment__c anaEnded = new Enrollment__c(
                Program__c = pantry.Id,
                Contact__c = ana.Id,
                Stage__c = 'Completed',
                Start_Date__c = Date.today().addDays(-5),
                End_Date__c = Date.today().addDays(-1)
            );
            Enrollment__c anaOpen = new Enrollment__c(
                Program__c = pantry.Id,
                Contact__c = ana.Id,
                Start_Date__c = Date.today().addDays(-30)
            );
            Enrollment__c benEnded = new Enrollment__c(
                Program__c = pantry.Id,
                Contact__c = ben.Id,
                Stage__c = 'Withdrawn',
                Start_Date__c = Date.today().addDays(-30),
                End_Date__c = Date.today().addDays(-10)
            );
            insert new List<Enrollment__c>{ anaEnded, anaOpen, benEnded };
            List<Service_Delivery__c> deliveries = new List<Service_Delivery__c>{
                new Service_Delivery__c(Service__c = meal.Id, Contact__c = ana.Id),
                new Service_Delivery__c(Service__c = meal.Id, Contact__c = ben.Id),
                new Service_Delivery__c(Service__c = meal.Id, Contact__c = cal.Id)
            };

            Test.startTest();
            insert deliveries;
            Test.stopTest();

            Assert.areEqual(anaOpen.Id, saved(deliveries[0].Id).Enrollment__c, 'The open one.');
            Assert.areEqual(benEnded.Id, saved(deliveries[1].Id).Enrollment__c, 'Else the last.');
            Assert.isNull(saved(deliveries[2].Id).Enrollment__c, 'Still recorded, unlinked.');
        }
    }

    @IsTest
    static void refusesTwoPeopleANegativeQuantityAndDeletingAServiceInUse() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c pantry = new Program__c(Name = 'Pantry');
            insert pantry;
            Service__c meal = serviceIn(pantry);
            Contact ana = person('Rivera');
            List<Database.SaveResult> results = Database.insert(
                new List<Service_Delivery__c>{
                    new Service_Delivery__c(Service__c = meal.Id),
                    new Service_Delivery__c(
                        Service__c = meal.Id,
                        Contact__c = ana.Id,
                        Quantity__c = -1
                    ),
                    new Service_Delivery__c(Service__c = meal.Id, Contact__c = ana.Id)
                },
                false
            );
            Assert.isFalse(results[0].isSuccess(), 'Nobody named is refused.');
            Assert.isFalse(results[1].isSuccess(), 'A negative quantity is refused.');
            Assert.isTrue(results[2].isSuccess(), 'A plain delivery saves.');

            Test.startTest();
            Database.DeleteResult removed = Database.delete(meal, false);
            Test.stopTest();

            Assert.isFalse(removed.isSuccess(), 'A service with deliveries is kept.');
        }
    }
}
