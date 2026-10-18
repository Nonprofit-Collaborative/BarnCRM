/**
 * Skills, volunteer skills and job skills (V-04; canonical model Sections 29P to 29R): one
 * person per volunteer skill (R-VK1), a skill in use cannot be deleted (R-SK1), a repeated
 * pair is harmless (R-VK2), bulk loads, a person held as an account, and what each packaged
 * permission set may do. These objects have no Apex: the rules are validation rules and
 * delete constraints, so this proves the metadata.
 */
@IsTest
private class VolunteerSkillTest {
    private static final Integer ROWS = 251;
    private static final String COORDINATOR = 'SkillCoordinator';
    private static final String STAFFER = 'SkillStaffer';
    private static final String READER = 'SkillReader';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            TestUsers.standardUserWith(
                COORDINATOR,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
            );
            TestUsers.standardUserWith(
                STAFFER,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Staff' }
            );
            TestUsers.standardUserWith(
                READER,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Read_Only' }
            );
        }
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static Skill__c skill(String name) {
        Skill__c record = new Skill__c(Name = name, Active__c = true);
        insert record;
        return record;
    }

    private static String insertError(SObject record) {
        try {
            insert record;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        } catch (TypeException noCreate) {
            return noCreate.getMessage(); // A user with no create right on the object.
        }
        return '';
    }

    private static String deleteError(SObject record) {
        try {
            delete record;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        } catch (TypeException noDelete) {
            return noDelete.getMessage();
        }
        return '';
    }

    @IsTest
    static void aSkillDefaultsToActiveAndAVolunteerSkillToTypeSkill() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Skill__c spanish = new Skill__c(Name = 'Spanish');
            insert spanish;
            Contact person = VolunteersTestData.contact('Rivera', null);

            Volunteer_Skill__c held = new Volunteer_Skill__c(
                Contact__c = person.Id,
                Skill__c = spanish.Id
            );
            insert held;

            Assert.isTrue(
                [SELECT Active__c FROM Skill__c WHERE Id = :spanish.Id].Active__c,
                'A new skill is offered by default'
            );
            Assert.areEqual(
                'Skill',
                [SELECT Type__c FROM Volunteer_Skill__c WHERE Id = :held.Id].Type__c,
                'A held skill is a Skill unless it is marked Interest'
            );
        }
    }

    @IsTest
    static void aVolunteerSkillNamesExactlyOnePerson() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Skill__c spanish = skill('Spanish');
            Contact person = VolunteersTestData.contact('Rivera', null);
            Account other = VolunteersTestData.household('The Okafor Family');

            String neither = insertError(new Volunteer_Skill__c(Skill__c = spanish.Id));
            String both = insertError(
                new Volunteer_Skill__c(
                    Skill__c = spanish.Id,
                    Contact__c = person.Id,
                    Account__c = other.Id
                )
            );

            Assert.isTrue(neither.contains('contact or an account'), 'None is refused: ' + neither);
            Assert.isTrue(both.contains('contact or an account'), 'Both is refused: ' + both);
            Assert.areEqual(0, [SELECT COUNT() FROM Volunteer_Skill__c], 'Nothing was saved');
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountCanHoldASkill() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Account person = VolunteersTestData.personAccount('Okafor');
            if (person == null) {
                return; // An org without person accounts has no such person.
            }
            Skill__c spanish = skill('Spanish');

            Volunteer_Skill__c held = new Volunteer_Skill__c(
                Account__c = person.Id,
                Skill__c = spanish.Id,
                Type__c = 'Interest'
            );
            insert held;

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Skill__c WHERE Account__c = :person.Id],
                'The person account holds the interest'
            );
        }
    }

    @IsTest
    static void aRepeatedPairIsHarmless() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Skill__c spanish = skill('Spanish');
            Contact person = VolunteersTestData.contact('Rivera', null);
            Volunteer_Skill__c first = new Volunteer_Skill__c(
                Contact__c = person.Id,
                Skill__c = spanish.Id
            );
            Volunteer_Skill__c again = first.clone(false);

            insert new List<Volunteer_Skill__c>{ first, again };

            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Volunteer_Skill__c WHERE Contact__c = :person.Id],
                'Nothing guards a pair written twice: matching asks whether, not how many (R-VK2)'
            );
        }
    }

    @IsTest
    static void aSkillInUseCannotBeDeletedButAnUnusedOneCan() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Skill__c heldByPerson = skill('Spanish');
            Skill__c neededByJob = skill('Forklift licence');
            Skill__c unused = skill('Gardening');
            Contact person = VolunteersTestData.contact('Rivera', null);
            Volunteer_Job__c job = VolunteersTestData.job('Warehouse');
            insert new Volunteer_Skill__c(Contact__c = person.Id, Skill__c = heldByPerson.Id);
            insert new Job_Skill__c(Job__c = job.Id, Skill__c = neededByJob.Id);

            String heldRefusal = deleteError(heldByPerson);
            String neededRefusal = deleteError(neededByJob);
            String unusedRefusal = deleteError(unused);

            Assert.areNotEqual('', heldRefusal, 'A skill a person holds is kept (R-SK1)');
            Assert.areNotEqual('', neededRefusal, 'A skill a job needs is kept (R-SK1)');
            Assert.areEqual('', unusedRefusal, 'An unused skill can go');

            update new Skill__c(Id = heldByPerson.Id, Active__c = false);
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Skill__c WHERE Skill__c = :heldByPerson.Id],
                'An inactive skill stays on the people who hold it'
            );
        }
    }

    @IsTest
    static void aRetiredSkillIsRefusedForNewRowsAndKeptOnOldOnes() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Skill__c retired = skill('Typing');
            Skill__c active = skill('Spanish');
            Contact person = VolunteersTestData.contact('Rivera', null);
            Volunteer_Job__c job = VolunteersTestData.job('Office');
            Volunteer_Skill__c held = new Volunteer_Skill__c(
                Contact__c = person.Id,
                Skill__c = active.Id
            );
            insert held;
            insert new Job_Skill__c(Job__c = job.Id, Skill__c = retired.Id);
            update new Skill__c(Id = retired.Id, Active__c = false);

            String personRefusal = insertError(
                new Volunteer_Skill__c(Contact__c = person.Id, Skill__c = retired.Id)
            );
            String jobRefusal = insertError(
                new Job_Skill__c(Job__c = job.Id, Skill__c = retired.Id)
            );
            String moveRefusal = '';
            try {
                update new Volunteer_Skill__c(Id = held.Id, Skill__c = retired.Id);
            } catch (DmlException refused) {
                moveRefusal = refused.getDmlMessage(0);
            }
            update new Volunteer_Skill__c(Id = held.Id, Type__c = 'Interest');

            Assert.isTrue(
                personRefusal.contains('retired'),
                'Not given to a person: ' + personRefusal
            );
            Assert.isTrue(jobRefusal.contains('retired'), 'Not added to a job: ' + jobRefusal);
            Assert.isTrue(moveRefusal.contains('retired'), 'A row is not moved onto it');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Job_Skill__c WHERE Skill__c = :retired.Id],
                'The job that needed it keeps it, and the job can still be saved'
            );
            Assert.areEqual(
                'Interest',
                [SELECT Type__c FROM Volunteer_Skill__c WHERE Id = :held.Id].Type__c,
                'A row whose skill is unchanged saves as before'
            );
        }
    }

    @IsTest
    static void deletingAJobDeletesItsJobSkills() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Skill__c forklift = skill('Forklift licence');
            Volunteer_Job__c job = VolunteersTestData.job('Warehouse');
            insert new Job_Skill__c(Job__c = job.Id, Skill__c = forklift.Id);

            delete job;

            Assert.areEqual(0, [SELECT COUNT() FROM Job_Skill__c], 'Job skills go with the job');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Skill__c WHERE Id = :forklift.Id],
                'The skill itself stays'
            );
        }
    }

    @IsTest
    static void aBulkLoadOf251SavesAndRefusesTheBadRowsOnly() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            List<Skill__c> skills = new List<Skill__c>();
            for (Integer i = 0; i < ROWS; i++) {
                skills.add(new Skill__c(Name = 'Skill ' + i, Active__c = true));
            }
            insert skills;
            List<Contact> people = VolunteersTestData.contacts(ROWS);
            Volunteer_Job__c job = VolunteersTestData.job('Warehouse');

            List<Volunteer_Skill__c> held = new List<Volunteer_Skill__c>();
            List<Job_Skill__c> needed = new List<Job_Skill__c>();
            for (Integer i = 0; i < ROWS; i++) {
                held.add(
                    new Volunteer_Skill__c(Contact__c = people[i].Id, Skill__c = skills[i].Id)
                );
                needed.add(new Job_Skill__c(Job__c = job.Id, Skill__c = skills[i].Id));
            }
            // Row 0 names nobody: only that row is refused.
            held[0].Contact__c = null;

            Test.startTest();
            List<Database.SaveResult> heldResults = Database.insert(held, false);
            List<Database.SaveResult> neededResults = Database.insert(needed, false);
            Test.stopTest();

            Assert.isFalse(heldResults[0].isSuccess(), 'The row with no person is refused');
            Integer saved = 0;
            for (Database.SaveResult result : heldResults) {
                saved += result.isSuccess() ? 1 : 0;
            }
            Assert.areEqual(ROWS - 1, saved, 'Every other volunteer skill is saved');
            Assert.areEqual(ROWS, [SELECT COUNT() FROM Job_Skill__c], 'Every job skill is saved');
            for (Database.SaveResult result : neededResults) {
                Assert.isTrue(result.isSuccess(), 'A job skill saves');
            }
        }
    }

    @IsTest
    static void eachPermissionSetGrantsWhatTheAccessTableSays() {
        Skill__c spanish;
        Contact person;
        Contact coordinatorsPerson;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            spanish = skill('Spanish');
            person = VolunteersTestData.contact('Rivera', null);
            update new Contact(Id = person.Id, OwnerId = user(STAFFER).Id);
            coordinatorsPerson = VolunteersTestData.contact('Okafor', null);
            update new Contact(Id = coordinatorsPerson.Id, OwnerId = user(COORDINATOR).Id);
        }

        System.runAs(user(READER)) {
            Assert.areEqual(1, [SELECT COUNT() FROM Skill__c], 'Read Only sees the list');
            Assert.areNotEqual(
                '',
                insertError(new Skill__c(Name = 'Typing')),
                'Read Only creates no skill'
            );
            Assert.areNotEqual(
                '',
                insertError(new Volunteer_Skill__c(Contact__c = person.Id, Skill__c = spanish.Id)),
                'Read Only adds no volunteer skill'
            );
        }

        Volunteer_Skill__c stafferRow = new Volunteer_Skill__c(
            Contact__c = person.Id,
            Skill__c = spanish.Id
        );
        System.runAs(user(STAFFER)) {
            Assert.areNotEqual(
                '',
                insertError(new Skill__c(Name = 'Typing')),
                'Staff does not manage the list'
            );
            Assert.areEqual('', insertError(stafferRow), 'Staff adds a skill to a person');
            Volunteer_Skill__c removable = stafferRow.clone(false);
            Assert.areEqual('', insertError(removable), 'Staff adds another');
            Assert.areEqual('', deleteError(removable), 'Staff removes a row they added');
        }

        System.runAs(user(COORDINATOR)) {
            Skill__c typing = new Skill__c(Name = 'Typing');
            Assert.areEqual('', insertError(typing), 'A coordinator manages the list');
            update new Skill__c(Id = typing.Id, Active__c = false);
            Assert.isFalse(
                [SELECT Active__c FROM Skill__c WHERE Id = :typing.Id].Active__c,
                'A coordinator retires a skill'
            );
            Volunteer_Skill__c row = new Volunteer_Skill__c(
                Contact__c = coordinatorsPerson.Id,
                Skill__c = spanish.Id,
                Type__c = 'Interest'
            );
            Assert.areEqual('', insertError(row), 'A coordinator adds a person an interest');
            Volunteer_Skill__c staffers = [
                SELECT Id
                FROM Volunteer_Skill__c
                WHERE Contact__c = :person.Id
                LIMIT 1
            ];
            update new Volunteer_Skill__c(Id = staffers.Id, Type__c = 'Interest');
            Assert.areEqual(
                'Interest',
                [SELECT Type__c FROM Volunteer_Skill__c WHERE Id = :staffers.Id].Type__c,
                'A coordinator corrects a row someone else added (Modify All)'
            );
        }
    }
}
