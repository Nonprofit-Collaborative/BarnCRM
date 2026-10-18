/**
 * Volunteer requirements (V-05; canonical model Section 29S): one person (R-VQ1), the date rules
 * (R-VQ2), Is Current, a person held as an account, 251 at a time, and who may see them (R-VQ4).
 * The object has no Apex but its erasure extension, tested in
 * `VolunteersErasureExtensionTest`: the rules are validation rules and a formula.
 */
@IsTest
private class VolunteerRequirementTest {
    private static final Integer ROWS = 251;
    private static final String COORDINATOR = 'ReqCoordinator';
    private static final String STAFFER = 'ReqStaffer';
    private static final String READER = 'ReqReader';

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

    private static Volunteer_Requirement__c newRequirement(Id contactId, String type) {
        return new Volunteer_Requirement__c(Contact__c = contactId, Type__c = type);
    }

    private static String insertError(SObject record) {
        try {
            insert record;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        } catch (TypeException noCreate) {
            return noCreate.getMessage(); // A user with no create right on the object.
        } catch (SecurityException noAccess) {
            return noAccess.getMessage(); // A user with no access to the object at all.
        }
        return '';
    }

    @IsTest
    static void aNewRequirementIsNotStartedAndNotCurrent() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact person = VolunteersTestData.contact('Rivera', null);
            Volunteer_Requirement__c requirement = newRequirement(person.Id, 'Orientation');
            insert requirement;

            Volunteer_Requirement__c saved = [
                SELECT Status__c, Is_Current__c
                FROM Volunteer_Requirement__c
                WHERE Id = :requirement.Id
            ];
            Assert.areEqual('Not started', saved.Status__c, 'Not started by default');
            Assert.isFalse(saved.Is_Current__c, 'A step not completed is not current');
        }
    }

    @IsTest
    static void aRequirementNamesExactlyOnePerson() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact person = VolunteersTestData.contact('Rivera', null);
            Account other = VolunteersTestData.household('The Okafor Family');

            String neither = insertError(new Volunteer_Requirement__c(Type__c = 'Application'));
            Volunteer_Requirement__c both = newRequirement(person.Id, 'Application');
            both.Account__c = other.Id;

            Assert.isTrue(neither.contains('contact or an account'), 'None refused: ' + neither);
            Assert.isTrue(insertError(both).contains('contact or an account'), 'Both refused');
            Assert.areEqual(0, [SELECT COUNT() FROM Volunteer_Requirement__c], 'Nothing saved');
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountHasRequirements() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Account person = VolunteersTestData.personAccount('Okafor');
            if (person == null) {
                return; // An org without person accounts has no such person.
            }

            insert new Volunteer_Requirement__c(
                Account__c = person.Id,
                Type__c = 'Background check',
                Status__c = 'In progress'
            );

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Account__c = :person.Id],
                'The person account has the step'
            );
        }
    }

    @IsTest
    static void completedNeedsADateThatIsNotInTheFutureAndExpiryNotBeforeIt() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact person = VolunteersTestData.contact('Rivera', null);
            Date today = System.today();

            Volunteer_Requirement__c noDate = newRequirement(person.Id, 'Application');
            noDate.Status__c = 'Completed';
            Volunteer_Requirement__c future = newRequirement(person.Id, 'Application');
            future.Status__c = 'Completed';
            future.Completed_Date__c = today.addDays(1);
            Volunteer_Requirement__c backwards = newRequirement(person.Id, 'Application');
            backwards.Status__c = 'Completed';
            backwards.Completed_Date__c = today.addDays(-10);
            backwards.Expires__c = today.addDays(-11);
            Volunteer_Requirement__c fine = newRequirement(person.Id, 'Application');
            fine.Status__c = 'Completed';
            fine.Completed_Date__c = today;
            fine.Expires__c = today;

            Assert.areNotEqual('', insertError(noDate), 'Completed needs its date');
            Assert.areNotEqual('', insertError(future), 'A completed date is not in the future');
            Assert.areNotEqual('', insertError(backwards), 'Expiry is not before completion');
            Assert.areEqual('', insertError(fine), 'Expiring the day it was completed is allowed');
        }
    }

    @IsTest
    static void isCurrentFollowsStatusAndExpiry() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact person = VolunteersTestData.contact('Rivera', null);
            Date today = System.today();
            Volunteer_Requirement__c open = newRequirement(person.Id, 'Orientation');
            open.Status__c = 'Completed';
            open.Completed_Date__c = today.addYears(-1);
            Volunteer_Requirement__c valid = newRequirement(person.Id, 'Background check');
            valid.Status__c = 'Completed';
            valid.Completed_Date__c = today.addDays(-30);
            valid.Expires__c = today.addYears(2);
            Volunteer_Requirement__c lapsed = newRequirement(person.Id, 'Background check');
            lapsed.Status__c = 'Completed';
            lapsed.Completed_Date__c = today.addYears(-3);
            lapsed.Expires__c = today.addDays(-1);
            Volunteer_Requirement__c refused = newRequirement(person.Id, 'Application');
            refused.Status__c = 'Not approved';
            insert new List<Volunteer_Requirement__c>{ open, valid, lapsed, refused };

            Map<Id, Volunteer_Requirement__c> saved = new Map<Id, Volunteer_Requirement__c>(
                [SELECT Is_Current__c FROM Volunteer_Requirement__c]
            );

            Assert.isTrue(saved.get(open.Id).Is_Current__c, 'Completed with no expiry is current');
            Assert.isTrue(saved.get(valid.Id).Is_Current__c, 'Completed and not yet expired');
            Assert.isFalse(saved.get(lapsed.Id).Is_Current__c, 'An expired step is not current');
            Assert.isFalse(saved.get(refused.Id).Is_Current__c, 'Not approved is not current');
        }
    }

    @IsTest
    static void aBulkLoadOf251SavesAndRefusesTheBadRowsOnly() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            List<Contact> people = VolunteersTestData.contacts(ROWS);
            List<Volunteer_Requirement__c> batch = new List<Volunteer_Requirement__c>();
            for (Integer i = 0; i < ROWS; i++) {
                Volunteer_Requirement__c row = newRequirement(people[i].Id, 'Orientation');
                row.Status__c = 'Completed';
                row.Completed_Date__c = System.today().addDays(-i);
                batch.add(row);
            }
            batch[0].Completed_Date__c = null; // Completed with no date.

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(batch, false);
            Test.stopTest();

            Assert.isFalse(results[0].isSuccess(), 'The undated completed row is refused');
            Integer saved = 0;
            for (Database.SaveResult result : results) {
                saved += result.isSuccess() ? 1 : 0;
            }
            Assert.areEqual(ROWS - 1, saved, 'Every other row is saved');
        }
    }

    @IsTest
    static void onlyAdminsAndCoordinatorsSeeOrEditRequirements() {
        Contact person;
        Volunteer_Requirement__c requirement;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            person = VolunteersTestData.contact('Rivera', null);
            // Let each of the three see the person; the requirement is the thing in question.
            requirement = newRequirement(person.Id, 'Background check');
            requirement.Notes__c = 'Ref 1234';
            insert requirement;
        }

        System.runAs(user(COORDINATOR)) {
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Requirement__c],
                'A coordinator sees every requirement, though the admin owns it'
            );
            update new Volunteer_Requirement__c(Id = requirement.Id, Status__c = 'In progress');
            Assert.areEqual(
                'In progress',
                [SELECT Status__c FROM Volunteer_Requirement__c WHERE Id = :requirement.Id]
                .Status__c,
                'A coordinator edits any requirement'
            );
        }
        System.runAs(user(STAFFER)) {
            Assert.areNotEqual(
                '',
                insertError(newRequirement(person.Id, 'Orientation')),
                'Staff creates no requirement'
            );
            Assert.isFalse(
                Schema.SObjectType.Volunteer_Requirement__c.isAccessible(),
                'Staff has no access to the object'
            );
        }
        System.runAs(user(READER)) {
            Assert.isFalse(
                Schema.SObjectType.Volunteer_Requirement__c.isAccessible(),
                'Read Only has no access to the object'
            );
        }
    }
}
