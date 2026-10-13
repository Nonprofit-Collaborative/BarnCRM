/**
 * Erasing a person (canonical model Section 29H): what is emptied, deleted and ended, what
 * happens to the households they leave, the preview, the refusals, the module seam, and two
 * hundred records at a time. Core's own tests see no installed module (`noneForTest`).
 */
@IsTest
private class PersonErasureTest {
    private static final String ERASE_SET = 'BarnCRM_Erase_People';

    private static User eraser() {
        return TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, ERASE_SET });
    }

    private static void isolate() {
        PersonErasureExtensions.noneForTest = true;
    }

    /** Jordan and Sam Lee in one household, in contact mode. Answers Jordan. */
    private static Contact coupleInContactMode(Boolean deleteEmpty) {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Delete_Empty_Households__c = deleteEmpty;
        HouseholdTestDataFactory.save(settings);
        Contact jordan = new Contact(
            FirstName = 'Jordan',
            LastName = 'Lee',
            Email = 'jordan@example.invalid',
            Phone = '555-0100',
            Birthdate = Date.newInstance(1980, 5, 1),
            Description = 'Met at the gala'
        );
        insert jordan;
        return [SELECT Id, Name, AccountId FROM Contact WHERE Id = :jordan.Id];
    }

    private static Contact addSam(Id householdId) {
        Contact sam = new Contact(FirstName = 'Sam', LastName = 'Lee', AccountId = householdId);
        insert sam;
        return sam;
    }

    @IsTest
    static void erasesTheContactItsAddressesAndConnectionsAndAudits() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(true);
            Contact sam = addSam(jordan.AccountId);
            insert new Address__c(
                Contact__c = jordan.Id,
                Type__c = 'Home',
                City__c = 'Springfield'
            );
            insert RelationshipTestDataFactory.between(jordan, sam, 'Spouse');
            Account employer = RelationshipTestDataFactory.organizations(1, 'Union')[0];
            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                jordan,
                employer,
                'Chair'
            );
            work.Is_Primary__c = true;
            work.Description__c = 'Board since 2019';
            insert work;

            Test.startTest();
            PersonErasure.Result result = PersonErasure.erase(
                jordan.Id,
                ' jordan  LEE ',
                'PR-2041'
            );
            Test.stopTest();

            Assert.isTrue(result.erased, 'The erasure ran');
            Contact erased = [
                SELECT
                    FirstName,
                    LastName,
                    Email,
                    Phone,
                    Birthdate,
                    Description,
                    AccountId,
                    HasOptedOutOfEmail
                FROM Contact
                WHERE Id = :jordan.Id
            ];
            Assert.areEqual(Label.Core_Erase_PersonName, erased.LastName, 'Named as erased');
            Assert.isNull(erased.FirstName, 'First name emptied');
            Assert.isNull(erased.Email, 'Email emptied');
            Assert.isNull(erased.Phone, 'Phone emptied');
            Assert.isNull(erased.Birthdate, 'Birth date emptied');
            Assert.isNull(erased.Description, 'Notes emptied');
            Assert.isNull(erased.AccountId, 'Left the household');
            Assert.isTrue(erased.HasOptedOutOfEmail, 'Opted out so no mailing reaches the record');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Address__c WHERE Contact__c = :jordan.Id],
                'Address deleted'
            );
            for (Relationship__c side : [SELECT End_Date__c, Status__c FROM Relationship__c]) {
                Assert.areEqual(Date.today(), side.End_Date__c, 'Both sides ended today');
            }
            Affiliation__c ended = [
                SELECT End_Date__c, Role__c, Description__c, Is_Primary__c
                FROM Affiliation__c
                WHERE Id = :work.Id
            ];
            Assert.areEqual(Date.today(), ended.End_Date__c, 'Affiliation ended');
            Assert.isNull(ended.Role__c, 'Role emptied');
            Assert.isNull(ended.Description__c, 'Description emptied');
            Assert.isFalse(ended.Is_Primary__c, 'No longer primary');
            Account household = [SELECT Member_Count__c FROM Account WHERE Id = :jordan.AccountId];
            Assert.areEqual(1, household.Member_Count__c, 'Recounted without Jordan');

            Erasure__c audit = [
                SELECT Contact__c, Erased_Record_Id__c, Request_Reference__c, Details__c
                FROM Erasure__c
                WHERE Id = :result.erasureId
            ];
            Assert.areEqual(jordan.Id, audit.Contact__c, 'The audit names the record');
            Assert.areEqual('PR-2041', audit.Request_Reference__c, 'And the request');
            Assert.isFalse(audit.Details__c.contains('Jordan'), 'No erased value in the audit');
            Assert.isFalse(audit.Details__c.contains('example.invalid'), 'Not even the email');
            Assert.isTrue(
                audit.Details__c.contains(String.valueOf(work.Id)),
                'Each record changed is listed'
            );
        }
    }

    @IsTest
    static void theOnlyMembersHouseholdIsDeletedWhenTheSettingIsOn() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(true);

            PersonErasure.erase(jordan.Id, jordan.Name, null);

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :jordan.AccountId],
                'Tidied away'
            );
        }
    }

    @IsTest
    static void theOnlyMembersHouseholdIsAnonymizedWhenKept() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(false);
            update new Account(
                Id = jordan.AccountId,
                BillingCity = 'Springfield',
                Phone = '555-0101'
            );
            insert new Address__c(
                Account__c = jordan.AccountId,
                Type__c = 'Home',
                City__c = 'Springfield'
            );

            PersonErasure.Result result = PersonErasure.erase(jordan.Id, jordan.Name, null);

            Account kept = [
                SELECT Name, Custom_Name__c, BillingCity, Phone, Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :jordan.AccountId
            ];
            Assert.areEqual(Label.Core_Erase_HouseholdName, kept.Name, 'Renamed');
            Assert.isTrue(kept.Custom_Name__c, 'Naming will not put the name back');
            Assert.isNull(kept.BillingCity, 'Address emptied');
            Assert.isNull(kept.Phone, 'Phone emptied');
            Assert.isNull(kept.Household_Informal_Greeting__c, 'Greeting emptied');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Address__c WHERE Account__c = :jordan.AccountId],
                'Its addresses deleted'
            );
            Assert.isFalse(result.changes.isEmpty(), 'Reported');
        }
    }

    @IsTest
    static void junctionModeEndsTheMembership() {
        System.runAs(eraser()) {
            isolate();
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert household;
            Contact jordan = HouseholdTestDataFactory.newContact('Jordan', 'Lee');
            Contact sam = HouseholdTestDataFactory.newContact('Sam', 'Lee');
            insert new List<Contact>{ jordan, sam };
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = household.Id,
                    Contact__c = jordan.Id,
                    Is_Primary__c = true
                ),
                new Household_Member__c(Household__c = household.Id, Contact__c = sam.Id)
            };

            PersonErasure.erase(jordan.Id, 'Jordan Lee', null);

            Household_Member__c membership = [
                SELECT End_Date__c, Is_Primary__c
                FROM Household_Member__c
                WHERE Contact__c = :jordan.Id
            ];
            Assert.areEqual(
                Date.today(),
                membership.End_Date__c,
                'Membership ended, kept as history'
            );
            Assert.isFalse(membership.Is_Primary__c, 'No longer primary');
            Account recounted = [SELECT Member_Count__c FROM Account WHERE Id = :household.Id];
            Assert.areEqual(1, recounted.Member_Count__c, 'Recounted without Jordan');
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountIsErasedTheSameWay() {
        System.runAs(eraser()) {
            isolate();
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Account> people = RelationshipTestDataFactory.peopleAsAccounts(2, 'Okafor');
            Account employer = RelationshipTestDataFactory.organizations(1, 'Union')[0];
            insert RelationshipTestDataFactory.affiliation(people[0], employer, 'Trustee');
            insert RelationshipTestDataFactory.between(people[0], people[1], 'Sibling');
            insert new Address__c(
                Person_Account__c = people[0].Id,
                Type__c = 'Home',
                City__c = 'Lagos'
            );
            update new Account(
                Id = people[0].Id,
                Phone = '555-0102',
                Description = 'Prefers calls'
            );
            // An ordinary account stands in for a person account (RelationshipTestDataFactory).
            PersonRecordSelector.personRecordOverride = true;

            PersonErasure.Result result = PersonErasure.erase(people[0].Id, 'Person0 Okafor', null);

            Account erased = [
                SELECT Name, Phone, Description
                FROM Account
                WHERE Id = :people[0].Id
            ];
            Assert.areEqual(Label.Core_Erase_PersonName, erased.Name, 'Named as erased');
            Assert.isNull(erased.Phone, 'Phone emptied');
            Assert.isNull(erased.Description, 'Notes emptied');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Address__c WHERE Person_Account__c = :people[0].Id],
                'Address deleted'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Affiliation__c
                    WHERE Person_Account__c = :people[0].Id AND End_Date__c = NULL
                ],
                'Affiliation ended'
            );
            Erasure__c audit = [
                SELECT Person_Account__c
                FROM Erasure__c
                WHERE Id = :result.erasureId
            ];
            Assert.areEqual(people[0].Id, audit.Person_Account__c, 'The audit names the account');
        }
    }

    @IsTest
    static void thePreviewListsTheChangesAndChangesNothing() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(true);
            insert new Address__c(
                Contact__c = jordan.Id,
                Type__c = 'Home',
                City__c = 'Springfield'
            );

            PersonErasure.Result result = PersonErasure.preview(jordan.Id);

            Set<String> actions = new Set<String>();
            for (PersonErasure.Change change : result.changes) {
                actions.add(change.action + ' ' + change.objectLabel);
            }
            Assert.isTrue(
                actions.contains(
                    PersonErasure.CLEARED +
                        ' ' +
                        Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel()
                ),
                'Lists the person'
            );
            Assert.isTrue(
                actions.contains(
                    PersonErasure.DELETED +
                        ' ' +
                        Address__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                            .getLabel()
                ),
                'Lists the address'
            );
            Assert.isTrue(
                actions.contains(PersonErasure.DELETED + ' ' + Label.Core_Erase_Household),
                'Lists the household'
            );
            Assert.isFalse(result.erased, 'A preview erases nothing');
            Assert.areEqual(
                'Jordan',
                [SELECT FirstName FROM Contact WHERE Id = :jordan.Id].FirstName,
                'Person unchanged'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Address__c WHERE Contact__c = :jordan.Id],
                'Address still there'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :jordan.AccountId],
                'Household still there'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Erasure__c], 'No audit for a preview');
        }
    }

    @IsTest
    static void activitiesAndFilesAreCountedForTheAdminToDeleteByHand() {
        System.runAs(eraser()) {
            isolate();
            // Household kept, so no account delete can take activities with it.
            Contact jordan = coupleInContactMode(false);
            insert new List<Task>{
                new Task(WhoId = jordan.Id, Subject = 'Call'),
                new Task(WhoId = jordan.Id, Subject = 'Thank you note')
            };
            insert new Event(
                WhoId = jordan.Id,
                Subject = 'Visit',
                ActivityDateTime = System.now(),
                DurationInMinutes = 30
            );
            insert new ContentVersion(
                Title = 'Letter',
                PathOnClient = 'letter.txt',
                VersionData = Blob.valueOf('Dear Jordan'),
                FirstPublishLocationId = jordan.Id
            );

            Map<String, PersonErasure.Change> kept = new Map<String, PersonErasure.Change>();
            for (PersonErasure.Change change : PersonErasure.preview(jordan.Id).changes) {
                if (change.action == PersonErasure.KEPT) {
                    kept.put(change.objectLabel, change);
                }
            }
            String tasks = Task.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
            String events = Event.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getLabel();
            Assert.areEqual(2, kept.get(tasks)?.count, 'Both tasks counted');
            Assert.areEqual(1, kept.get(events)?.count, 'The event counted');
            Assert.areEqual(1, kept.get(Label.Core_Erase_Files)?.count, 'The file counted');
            Assert.areEqual(
                Label.Core_Erase_NoteByHand,
                kept.get(tasks).note,
                'Told to act by hand'
            );

            Test.startTest();
            PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Task WHERE WhoId = :jordan.Id],
                'Nothing is erased automatically (R-ER10)'
            );
        }
    }

    @IsTest
    static void withoutThePermissionNothingIsErased() {
        Contact jordan;
        System.runAs(TestUsers.admin()) {
            jordan = coupleInContactMode(true);
        }
        System.runAs(TestUsers.admin()) {
            isolate();
            try {
                PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
                Assert.fail('Refused without Erase People');
            } catch (PersonErasure.ErasureException refused) {
                Assert.areEqual(
                    Label.Core_Erase_NoPermission,
                    refused.getMessage(),
                    'Says which permission'
                );
            }
            Assert.areEqual(
                'Jordan',
                [SELECT FirstName FROM Contact WHERE Id = :jordan.Id].FirstName,
                'Unchanged'
            );
        }
    }

    @IsTest
    static void aUserWhoCannotEditThePersonIsRefusedWithAReason() {
        Contact jordan;
        System.runAs(TestUsers.admin()) {
            jordan = coupleInContactMode(true);
        }
        System.runAs(TestUsers.withPermissionSets(
            new List<String>{ 'BarnCRM_Read_Only', ERASE_SET }
        )) {
            isolate();
            try {
                PersonErasure.preview(jordan.Id);
                Assert.fail('Refused for a person the user cannot edit');
            } catch (PersonErasure.ErasureException refused) {
                Assert.isTrue(
                    refused.getMessage()
                        .contains(
                            Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                                .getLabelPlural()
                        ),
                    'Names what is in the way'
                );
            }
        }
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'Jordan',
                [SELECT FirstName FROM Contact WHERE Id = :jordan.Id].FirstName,
                'Unchanged'
            );
        }
    }

    @IsTest
    static void aWrongNameOrASecondErasureIsRefused() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(true);
            try {
                PersonErasure.erase(jordan.Id, 'Jordan Leigh', null);
                Assert.fail('Refused for a name that does not match');
            } catch (PersonErasure.ErasureException refused) {
                Assert.areEqual(
                    Label.Core_Erase_NameMismatch,
                    refused.getMessage(),
                    'Asks for the name'
                );
            }
            PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
            try {
                PersonErasure.erase(jordan.Id, Label.Core_Erase_PersonName, null);
                Assert.fail('Refused a second time');
            } catch (PersonErasure.ErasureException refused) {
                Assert.isTrue(
                    refused.getMessage()
                        .startsWith(Label.Core_Erase_AlreadyErased.substringBefore('{0}')),
                    'Already erased'
                );
            }
        }
    }

    @IsTest
    static void aModuleKeepsItsFieldsAndReportsItsRecords() {
        System.runAs(eraser()) {
            isolate();
            PersonErasureExtensions.overrides.add(new KeepsDepartment());
            Contact jordan = coupleInContactMode(true);
            update new Contact(Id = jordan.Id, Department = 'Major donors');

            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Jordan Lee', null);

            Assert.areEqual(
                'Major donors',
                [SELECT Department FROM Contact WHERE Id = :jordan.Id].Department,
                'Kept for the module'
            );
            Boolean reported = false;
            for (PersonErasure.Change change : result.changes) {
                reported |= change.objectLabel == 'Module record';
            }
            Assert.isTrue(reported, 'The module reports what it did');
        }
    }

    @IsTest
    static void aModuleThatFailsRefusesTheWholeErasure() {
        System.runAs(eraser()) {
            isolate();
            PersonErasureExtensions.overrides.add(new Fails());
            Contact jordan = coupleInContactMode(true);
            insert new Address__c(
                Contact__c = jordan.Id,
                Type__c = 'Home',
                City__c = 'Springfield'
            );
            try {
                PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
                Assert.fail('Refused');
            } catch (PersonErasure.ErasureException refused) {
                Assert.isTrue(refused.getMessage().contains('module failed'), 'Says why');
            }
            Assert.areEqual(
                'Jordan',
                [SELECT FirstName FROM Contact WHERE Id = :jordan.Id].FirstName,
                'Person unchanged'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Address__c WHERE Contact__c = :jordan.Id],
                'Address back'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Erasure__c], 'No audit');
        }
    }

    @IsTest
    static void twoHundredOfEachAreErasedInOneGo() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(true);
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Contact> others = RelationshipTestDataFactory.contacts(200, 'Friend');
            List<Account> orgs = RelationshipTestDataFactory.organizations(200, 'Org');
            List<Relationship__c> relationships = new List<Relationship__c>();
            List<Affiliation__c> affiliations = new List<Affiliation__c>();
            List<Address__c> addresses = new List<Address__c>();
            for (Integer i = 0; i < 200; i++) {
                relationships.add(RelationshipTestDataFactory.between(jordan, others[i], 'Friend'));
                affiliations.add(
                    RelationshipTestDataFactory.affiliation(jordan, orgs[i], 'Member')
                );
                addresses.add(
                    new Address__c(Contact__c = jordan.Id, Type__c = 'Other', City__c = 'City ' + i)
                );
            }
            insert relationships;
            insert affiliations;
            insert addresses;
            AutomationControl.clearAllBypasses();

            Test.startTest();
            PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Address__c WHERE Contact__c = :jordan.Id],
                'All addresses deleted'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Relationship__c WHERE End_Date__c = NULL],
                'Every relationship ended, both sides'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Affiliation__c WHERE End_Date__c = NULL],
                'Every affiliation ended'
            );
        }
    }

    @IsTest
    static void theAuditTextHoldsLabelsAndIdsOnly() {
        // runs-as: deploying user (pure logic: formats a list in memory, no DML or SOQL)
        PersonErasure.Change change = new PersonErasure.Change(
            PersonErasure.CLEARED,
            'Contact',
            new List<Id>{ FakeIds.of(Contact.SObjectType, 1) },
            new List<String>{ 'Email', 'Phone' }
        );
        String text = PersonErasure.details(new List<PersonErasure.Change>{ change });
        Assert.isTrue(text.startsWith('Cleared | Contact | 1 | Email, Phone | '), text);
    }

    private class KeepsDepartment implements PersonErasureExtension {
        public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
            return new Set<Schema.SObjectField>{ Contact.Department };
        }
        public List<PersonErasure.Change> erase(Id personId) {
            return new List<PersonErasure.Change>{
                new PersonErasure.Change(PersonErasure.KEPT, 'Module record', 3, 'Kept as records')
            };
        }
    }

    private class Fails implements PersonErasureExtension {
        public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
            return new Set<Schema.SObjectField>();
        }
        public List<PersonErasure.Change> erase(Id personId) {
            throw new PersonErasure.ErasureException('The module failed');
        }
    }
}
