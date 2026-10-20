/**
 * The Volunteers sample data set (C-10, canonical model Part G "Sample data"): the load builds
 * jobs, a schedule, shifts, sign-ups, hours in each status, skills and requirements for Core's
 * sample people, whichever way approval and attendance are set; the removal takes every one of
 * them, reopening Approved hours first, and leaves real records alone; and Core finds the module
 * by name. Run as a BarnCRM admin holding Volunteers Admin, the person who loads sample data.
 *
 * The stages are called directly, as Giving's tests do, because a test runs only the first
 * stage of a batch. The sample people are made the way Core's loader makes them: contacts,
 * flagged and keyed, in either membership mode.
 */
@IsTest(
    testFor='ApexClass:VolunteersSampleData, ApexClass:VolunteerSampleDataLoader, ApexClass:VolunteerSampleDataStages, ApexClass:VolunteerSampleDataRemoveStages, ApexClass:VolunteerSampleDataSelector'
)
private class VolunteerSampleDataTest {
    private static User admin() {
        return TestUsers.adminWith(VolunteersTestData.ADMIN);
    }

    private static List<Contact> samplePeople(Integer howMany) {
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
        VolunteerSampleDataStages stages = new VolunteerSampleDataStages();
        for (Integer stage = 0; stage < stages.stageCount(); stage++) {
            stages.runStage(stage);
        }
    }

    private static void removeEverything() {
        VolunteerSampleDataRemoveStages stages = new VolunteerSampleDataRemoveStages();
        Integer stageCount = stages.stageCount();
        for (Integer stage = 0; stage < stageCount; stage++) {
            stages.runStage(stage);
        }
    }

    private static Map<String, Integer> hoursByStatus() {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AggregateResult row : [
            SELECT Status__c status, COUNT(Id) entries
            FROM Volunteer_Hours__c
            WHERE Volunteer_Job__r.Sample_Data__c = TRUE
            GROUP BY Status__c
        ]) {
            counts.put((String) row.get('status'), (Integer) row.get('entries'));
        }
        return counts;
    }

    private static Integer sampleRecordsLeft() {
        return [SELECT COUNT() FROM Volunteer_Job__c WHERE Sample_Data__c = TRUE] +
            [SELECT COUNT() FROM Skill__c WHERE Sample_Data__c = TRUE] +
            [SELECT COUNT() FROM Volunteer_Shift__c WHERE Volunteer_Job__r.Sample_Data__c = TRUE] +
            [SELECT COUNT() FROM Shift_Schedule__c WHERE Job__r.Sample_Data__c = TRUE] +
            [SELECT COUNT() FROM Volunteer_Hours__c WHERE Contact__r.Sample_Data__c = TRUE] +
            [SELECT COUNT() FROM Volunteer_Skill__c WHERE Contact__r.Sample_Data__c = TRUE] +
            [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Contact__r.Sample_Data__c = TRUE];
    }

    private static void assertTheWholeSet() {
        Assert.areEqual(3, [SELECT COUNT() FROM Volunteer_Job__c WHERE Sample_Data__c = TRUE]);
        Assert.areEqual(4, [SELECT COUNT() FROM Skill__c WHERE Sample_Data__c = TRUE]);
        Assert.areEqual(4, [SELECT COUNT() FROM Job_Skill__c WHERE Job__r.Sample_Data__c = TRUE]);
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Shift_Schedule__c WHERE Job__r.Sample_Data__c = TRUE]
        );
        Assert.areEqual(
            36,
            [SELECT COUNT() FROM Volunteer_Signup__c WHERE Status__c = 'Attended'],
            'Three people attended each of the twelve past shifts'
        );
        Assert.areEqual(
            8,
            [SELECT COUNT() FROM Volunteer_Signup__c WHERE Status__c IN ('Signed up', 'Confirmed')],
            'Two people are booked on each of the four upcoming shifts'
        );
        Map<String, Integer> statuses = hoursByStatus();
        Assert.areEqual(4, statuses.get(VolunteerHoursService.STATUS_SUBMITTED), 'Four wait');
        Assert.areEqual(2, statuses.get(VolunteerHoursService.STATUS_REJECTED), 'Two rejected');
        Assert.areEqual(54, statuses.get(VolunteerHoursService.STATUS_APPROVED), 'The rest count');
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Volunteer_Hours__c
                WHERE
                    Status__c = :VolunteerHoursService.STATUS_REJECTED
                    AND Rejection_Reason__c = NULL
            ],
            'A rejected entry says why'
        );
        Assert.areEqual(60, new VolunteersSampleData().countLoaded(), 'The card counts entries');
        Assert.areEqual(24, [SELECT COUNT() FROM Volunteer_Skill__c]);
        Assert.areEqual(8, [SELECT COUNT() FROM Volunteer_Requirement__c]);
    }

    @IsTest
    static void theLoadBuildsTheWholeSetWithHoursInEveryStatus() {
        System.runAs(admin()) {
            samplePeople(24);

            Test.startTest();
            loadEverything();
            Test.stopTest();

            assertTheWholeSet();
            Assert.isTrue(
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Shift_Schedule__c != NULL] > 0,
                'The schedule created its own shifts ahead, as any schedule does'
            );
        }
    }

    @IsTest
    static void theSameSetLoadsWithApprovalAndAttendanceHoursTurnedOff() {
        System.runAs(admin()) {
            VolunteersTestData.volunteerSettings(false, false);
            samplePeople(24);

            Test.startTest();
            loadEverything();
            Test.stopTest();

            assertTheWholeSet();
        }
    }

    @IsTest
    static void removalTakesEverySampleRecordAndLeavesRealOnesAlone() {
        System.runAs(admin()) {
            VolunteersTestData.volunteerSettings(false, true);
            List<Contact> people = samplePeople(24);
            loadEverything();
            Contact realPerson = VolunteersTestData.contact('Real', null);
            Volunteer_Job__c realJob = VolunteersTestData.job('Real job');
            insert VolunteersTestData.newHours(realPerson.Id, realJob.Id, 2);
            Skill__c realSkill = new Skill__c(Name = 'Real skill', Active__c = true);
            insert realSkill;
            insert new Volunteer_Skill__c(
                Contact__c = realPerson.Id,
                Skill__c = realSkill.Id,
                Type__c = 'Skill'
            );
            VolunteerSampleDataLoader.removeChunkSize = 25;

            Test.startTest();
            removeEverything();
            Test.stopTest();

            Assert.areEqual(0, sampleRecordsLeft(), 'Every Volunteers sample record is gone');
            Assert.areEqual(0, VolunteerSampleDataLoader.removeNext(), 'Nothing is left to take');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Hours__c WHERE Volunteer_Job__c = :realJob.Id],
                'A real entry, Approved, is untouched'
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Volunteer_Skill__c], 'The real skill stays');
            Assert.areEqual(
                people.size(),
                [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE],
                'The people are Core\'s to remove, after Volunteers'
            );
        }
    }

    /** Runs the removal and returns the message of the delete a protection refused, or null. */
    private static String removeUntilRefused() {
        try {
            removeEverything();
        } catch (DmlException refused) {
            return refused.getMessage();
        }
        return null;
    }

    private static Volunteer_Job__c sampleJob() {
        Volunteer_Job__c job = new Volunteer_Job__c(
            Name = 'Sample job',
            Active__c = true,
            Sample_Data__c = true
        );
        insert job;
        return job;
    }

    @IsTest
    static void aRealPersonsSignupOrHoursOnASampleShiftKeepTheShiftAndItsJob() {
        System.runAs(admin()) {
            Contact sampler = samplePeople(1)[0];
            Contact realPerson = VolunteersTestData.contact('Real', null);
            Volunteer_Job__c job = sampleJob();
            Volunteer_Shift__c booked = VolunteersTestData.newShift(
                job.Id,
                VolunteersTestData.SHIFT_START,
                3
            );
            Volunteer_Shift__c worked = VolunteersTestData.newShift(
                job.Id,
                VolunteersTestData.SHIFT_START.addDays(1),
                3
            );
            Volunteer_Shift__c sampleOnly = VolunteersTestData.newShift(
                job.Id,
                VolunteersTestData.SHIFT_START.addDays(2),
                3
            );
            insert new List<Volunteer_Shift__c>{ booked, worked, sampleOnly };
            Volunteer_Signup__c realSignup = VolunteersTestData.newSignup(booked.Id, realPerson.Id);
            insert new List<Volunteer_Signup__c>{
                realSignup,
                VolunteersTestData.newSignup(booked.Id, sampler.Id),
                VolunteersTestData.newSignup(sampleOnly.Id, sampler.Id)
            };
            Volunteer_Hours__c realHours = VolunteersTestData.newHours(realPerson.Id, job.Id, 2);
            realHours.Volunteer_Shift__c = worked.Id;
            insert realHours;

            Test.startTest();
            String refusal = removeUntilRefused();
            Test.stopTest();

            Assert.isTrue(
                refusal != null && refusal.contains(Label.Volunteers_Job_InUseNotDeletable),
                'R-VJ1 keeps the job and the removal stops with its message: ' + refusal
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Signup__c WHERE Id = :realSignup.Id],
                'The real sign-up stays'
            );
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Id IN (:booked.Id, :worked.Id)],
                'The shifts a real person is on stay'
            );
            Assert.areEqual(
                worked.Id,
                [SELECT Volunteer_Shift__c FROM Volunteer_Hours__c WHERE Id = :realHours.Id]
                .Volunteer_Shift__c,
                'The real entry still names its shift'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Signup__c WHERE Contact__c = :sampler.Id],
                'The sample person\'s sign-ups go, on a kept shift too'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Shift__c WHERE Id = :sampleOnly.Id],
                'A shift only sample people were on goes'
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Volunteer_Job__c WHERE Id = :job.Id]);
        }
    }

    @IsTest
    static void aRealPersonsVolunteerSkillOnASampleSkillKeepsTheSkill() {
        System.runAs(admin()) {
            Contact sampler = samplePeople(1)[0];
            Contact realPerson = VolunteersTestData.contact('Real', null);
            Skill__c skill = new Skill__c(Name = 'Sample skill', Active__c = true);
            skill.Sample_Data__c = true;
            insert skill;
            Volunteer_Skill__c realRow = new Volunteer_Skill__c(
                Contact__c = realPerson.Id,
                Skill__c = skill.Id,
                Type__c = 'Skill'
            );
            insert new List<Volunteer_Skill__c>{
                realRow,
                new Volunteer_Skill__c(
                    Contact__c = sampler.Id,
                    Skill__c = skill.Id,
                    Type__c = 'Skill'
                )
            };

            Test.startTest();
            String refusal = removeUntilRefused();
            Test.stopTest();

            Assert.isNotNull(refusal, 'The skill\'s Restrict lookup refuses the delete');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Skill__c WHERE Id = :realRow.Id],
                'The real person\'s skill stays'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Skill__c WHERE Contact__c = :sampler.Id],
                'The sample person\'s skill goes'
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Skill__c WHERE Id = :skill.Id], 'Kept');
        }
    }

    @IsTest
    static void twoHundredFiftyOneApprovedSampleEntriesAreReopenedAndRemoved() {
        System.runAs(admin()) {
            VolunteersTestData.volunteerSettings(false, true);
            Contact person = samplePeople(1)[0];
            Volunteer_Job__c job = new Volunteer_Job__c(
                Name = 'Sample job',
                Active__c = true,
                Sample_Data__c = true
            );
            insert job;
            List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>();
            for (Integer i = 0; i < 251; i++) {
                entries.add(VolunteersTestData.newHours(person.Id, job.Id, 1));
            }
            insert entries;
            Assert.areEqual(251, hoursByStatus().get(VolunteerHoursService.STATUS_APPROVED));

            Test.startTest();
            Integer stageCount = new VolunteerSampleDataRemoveStages().stageCount();
            removeEverything();
            Test.stopTest();

            Assert.areEqual(3, stageCount, 'Two chunks of hours, then the job');
            Assert.areEqual(0, sampleRecordsLeft(), 'Every entry and the job are gone');
        }
    }

    @IsTest
    static void personAccountsAndJunctionModeAreSafe() {
        System.runAs(admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account realPerson = VolunteersTestData.personAccount('Okafor');
            Volunteer_Job__c realJob = VolunteersTestData.job('Real job');
            if (realPerson != null) {
                Volunteer_Hours__c entry = VolunteersTestData.newHours(null, realJob.Id, 2);
                entry.Account__c = realPerson.Id;
                insert entry;
            }
            samplePeople(24);

            Test.startTest();
            loadEverything();
            Assert.areEqual(60, new VolunteersSampleData().countLoaded(), 'Loaded on contacts');
            removeEverything();
            Test.stopTest();

            Assert.areEqual(0, sampleRecordsLeft(), 'Removed in junction mode too');
            Assert.areEqual(
                realPerson == null ? 0 : 1,
                [SELECT COUNT() FROM Volunteer_Hours__c WHERE Volunteer_Job__c = :realJob.Id],
                'A person account\'s own entry is never sample data'
            );
        }
    }

    @IsTest
    static void coreFindsTheModuleAndItsBatchesStart() {
        System.runAs(admin()) {
            Object built = Type.forName('VolunteersSampleData').newInstance();
            Assert.isTrue(
                built instanceof SampleDataModule,
                'Core can build the class by its name and use it as a module'
            );
            VolunteersSampleData module = (VolunteersSampleData) built;
            Assert.areEqual('Volunteers', module.moduleName(), 'The name startAfter looks for');
            Assert.areEqual(
                'VolunteerSampleDataRemoveStages',
                new VolunteerSampleDataRemoveStages().name(),
                'The removal names itself in the Error Log'
            );
            Assert.areEqual('VolunteerSampleDataStages', new VolunteerSampleDataStages().name());
            Assert.isFalse(String.isBlank(module.countLabel()), 'The card has its wording');
            Assert.areEqual(0, module.countLoaded(), 'Nothing loaded yet');

            // With no sample people the jobs still load, and nothing is booked.
            Test.startTest();
            loadEverything();
            new VolunteerSampleDataStages().finish();
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Volunteer_Signup__c], 'Nobody to book');
            Assert.areEqual(0, [SELECT COUNT() FROM Volunteer_Hours__c], 'Nobody to credit');
        }
    }

    @IsTest
    static void enqueueLoadStartsTheStageBatch() {
        System.runAs(admin()) {
            Test.startTest();
            new VolunteersSampleData().enqueueLoad();
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
            new VolunteersSampleData().enqueueRemove();
            Test.stopTest();

            // With nothing to remove it finishes at once and hands on, so two batches may run.
            Assert.isTrue(
                [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'SampleDataRemoveBatch'] >=
                1,
                'The Volunteers removal runs in Core\'s removal batch'
            );
        }
    }

    @IsTest
    static void theRemovalHandsOnToTheModuleBeforeOrToCore() {
        System.runAs(admin()) {
            Test.startTest();
            new VolunteerSampleDataRemoveStages().finish();
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'SampleDataRemoveBatch'],
                'Giving\'s removal where Giving is installed, otherwise Core\'s'
            );
        }
    }
}
