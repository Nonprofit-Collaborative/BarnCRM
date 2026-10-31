/**
 * The Programs sample data set: the load builds three programs, five services and 18 enrollments
 * of Core's sample people through the enrollment rules; the removal takes every one of them and
 * leaves real records alone, keeping a sample program a real person is enrolled in and naming it
 * in the Error Log; and Core finds the module by name. Run as a BarnCRM admin holding Programs
 * Admin, the person who loads sample data. The stages are called directly, because a test runs
 * only the first stage of a batch.
 */
@IsTest(testFor='ApexClass:ProgramsSampleData, ApexClass:ProgramSampleDataLoader')
private class ProgramSampleDataTest {
    private static final String ADMIN = 'Programs_Admin';

    @TestSetup
    static void makeAdmin() {
        TestUsers.adminWith(ADMIN);
    }

    private static User admin() {
        return TestUsers.adminWith(ADMIN);
    }

    private static List<Contact> samplePeople(Integer howMany) {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
        List<Contact> people = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            Contact person = HouseholdTestDataFactory.newContact('Sample', 'Person' + i);
            person.Sample_Data__c = true;
            person.Sample_Data_Key__c = 'H' + String.valueOf(100 + i) + '-1';
            people.add(person);
        }
        insert people;
        return people;
    }

    private static void loadEverything() {
        ProgramsSampleData.LoadStages stages = new ProgramsSampleData.LoadStages();
        for (Integer stage = 0; stage < stages.stageCount(); stage++) {
            stages.runStage(stage);
        }
    }

    private static void removeEverything() {
        ProgramsSampleData.RemoveStages stages = new ProgramsSampleData.RemoveStages();
        Integer stageCount = stages.stageCount();
        for (Integer stage = 0; stage < stageCount; stage++) {
            stages.runStage(stage);
        }
    }

    private static Integer countAt(String stage) {
        return [SELECT COUNT() FROM Enrollment__c WHERE Stage__c = :stage];
    }

    @IsTest
    static void theLoadBuildsTheWholeSet() {
        System.runAs(admin()) {
            samplePeople(12);

            Test.startTest();
            loadEverything();
            Test.stopTest();

            Assert.areEqual(3, [SELECT COUNT() FROM Program__c WHERE Sample_Data__c = TRUE]);
            Assert.areEqual(5, [SELECT COUNT() FROM Service__c], 'Five services.');
            Assert.areEqual(18, [SELECT COUNT() FROM Enrollment__c], 'Eighteen enrollments.');
            Assert.areEqual(12, countAt('Enrolled'), 'Four in tutoring and eight in the pantry.');
            Assert.areEqual(1, countAt('Applied'), 'One applied.');
            Assert.areEqual(1, countAt('Withdrawn'), 'One withdrew.');
            Assert.areEqual(4, countAt('Completed'), 'Four completed summer reading.');
            Assert.areEqual(
                40,
                [SELECT COUNT() FROM Service_Delivery__c WHERE Enrollment__c != NULL],
                'Four weeks of bags for eight and two sessions for four, each linked.'
            );
            Assert.areEqual(
                0,
                [
                    SELECT Quantity__c
                    FROM Service_Delivery__c
                    WHERE Attendance__c = 'Unexcused Absence'
                ]
                .Quantity__c,
                'One missed week, which delivered nothing.'
            );
            Assert.areEqual(18, new ProgramsSampleData().countLoaded(), 'The card counts them.');
            Assert.isTrue(new ProgramsSampleData().hasSampleRecords(), 'Sample programs exist.');
        }
    }

    @IsTest
    static void fewSamplePeopleNeverBreakTheOneOpenEnrollmentRule() {
        System.runAs(admin()) {
            samplePeople(2);

            Test.startTest();
            loadEverything();
            Test.stopTest();

            Assert.isTrue(
                [SELECT COUNT() FROM Enrollment__c] > 0,
                'The two people are enrolled without a refused save.'
            );
        }
    }

    @IsTest
    static void removalTakesEverySampleRecordAndLeavesRealOnesAlone() {
        System.runAs(admin()) {
            samplePeople(12);
            loadEverything();
            Program__c real = new Program__c(Name = 'Our own program');
            insert real;
            Contact person = HouseholdTestDataFactory.newContact('Rita', 'Real');
            insert person;
            insert new Enrollment__c(Program__c = real.Id, Contact__c = person.Id);
            ProgramSampleDataLoader.removeChunkSize = 20;

            Test.startTest();
            removeEverything();
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Program__c WHERE Sample_Data__c = TRUE]);
            Assert.areEqual(0, [SELECT COUNT() FROM Service__c], 'Services went with them.');
            Assert.areEqual(1, [SELECT COUNT() FROM Enrollment__c], 'Only the real one is left.');
            Assert.areEqual(0, [SELECT COUNT() FROM Service_Delivery__c], 'Deliveries went first.');
            Assert.isFalse(new ProgramsSampleData().hasSampleRecords(), 'Nothing left.');
            Assert.isNull(ProgramSampleDataLoader.logWhatWasKept(), 'Nothing was kept.');
        }
    }

    @IsTest
    static void aRealPersonsEnrollmentKeepsTheSampleProgram() {
        System.runAs(admin()) {
            samplePeople(12);
            loadEverything();
            Program__c pantry = [SELECT Id FROM Program__c WHERE Name = 'Food pantry'];
            Contact person = HouseholdTestDataFactory.newContact('Rita', 'Real');
            insert person;
            insert new Enrollment__c(Program__c = pantry.Id, Contact__c = person.Id);

            Test.startTest();
            removeEverything();
            new ProgramsSampleData.RemoveStages().finish();
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Program__c WHERE Sample_Data__c = TRUE],
                'The pantry stays, with its real enrollment.'
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Enrollment__c], 'The real enrollment stays.');
            List<Error_Log__c> logged = [
                SELECT Message__c
                FROM Error_Log__c
                WHERE Context__c = 'ProgramsSampleData.RemoveStages'
            ];
            Assert.areEqual(1, logged.size(), 'One Warning names it.');
            Assert.isTrue(logged[0].Message__c.contains('Food pantry'), 'By name.');
        }
    }

    @IsTest
    static void coreFindsTheModuleAndHandsOn() {
        System.runAs(admin()) {
            Object built = Type.forName('ProgramsSampleData').newInstance();
            Assert.isTrue(built instanceof SampleDataModule, 'Core builds it by its name.');
            ProgramsSampleData module = (ProgramsSampleData) built;
            Assert.areEqual('Programs', module.moduleName(), 'The name startAfter looks for.');
            Assert.isFalse(String.isBlank(module.countLabel()), 'The card has its wording.');
            Assert.areEqual(0, module.countLoaded(), 'Nothing loaded yet.');
            Assert.areEqual(
                'ProgramsSampleData.LoadStages',
                new ProgramsSampleData.LoadStages().name()
            );

            // With no sample people the programs still load, and nobody is enrolled.
            Test.startTest();
            loadEverything();
            new ProgramsSampleData.LoadStages().finish();
            Test.stopTest();

            Assert.areEqual(3, [SELECT COUNT() FROM Program__c], 'The programs load.');
            Assert.areEqual(0, [SELECT COUNT() FROM Enrollment__c], 'Nobody to enroll.');
        }
    }

    @IsTest
    static void enqueueLoadStartsTheStageBatch() {
        System.runAs(admin()) {
            Test.startTest();
            new ProgramsSampleData().enqueueLoad();
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'SampleDataStageBatch']
            );
        }
    }

    @IsTest
    static void enqueueRemoveStartsTheRemovalBatch() {
        System.runAs(admin()) {
            Test.startTest();
            new ProgramsSampleData().enqueueRemove();
            Test.stopTest();

            Assert.isTrue(
                [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'SampleDataRemoveBatch'] >=
                1,
                'The Programs removal runs in Core\'s removal batch.'
            );
        }
    }
}
