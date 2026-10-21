/**
 * Erasing a person (canonical model Section 29H): what is emptied, deleted and ended, what
 * happens to the households they leave, the preview, the refusals, the module seam, and two
 * hundred records at a time. Core's own tests see no installed module (`noneForTest`).
 */
@IsTest(testFor='ApexClass:PersonErasure, ApexClass:PersonErasureExtensions')
private class PersonErasureTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String ERASE_SET = 'BarnCRM_Erase_People';

    private static User eraser() {
        return TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, ERASE_SET });
    }

    private static void isolate() {
        PersonErasureExtensions.noneForTest = true;
    }

    /**
     * Real person accounts, named as RelationshipTestDataFactory.peopleAsAccounts names its
     * stand-ins. Fails, naming the fix, where the org has person accounts but gives the
     * running user no person record type (PersonAccountTestShape).
     */
    private static List<Account> personAccounts(Integer howMany, String lastName) {
        Assert.isNull(PersonAccountTestShape.skipReason(), 'Person accounts can be created');
        Id personType = OrgShapeDetector.creatablePersonRecordTypeId();
        List<Account> people = new List<Account>();
        for (Integer i = 0; i < howMany; i++) {
            Account person = new Account(RecordTypeId = personType);
            person.put('FirstName', 'Person' + i); // person field, set by name
            person.put('LastName', lastName); // person field, set by name
            people.add(person);
        }
        insert people;
        return people;
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
            PersonErasure.Change householdRow;
            PersonErasure.Change personRow;
            for (PersonErasure.Change change : result.changes) {
                if (change.action == PersonErasure.CLEARED) {
                    if (change.objectLabel == Label.Core_Erase_Household) {
                        householdRow = change;
                    } else if (change.recordIds.contains(jordan.Id)) {
                        personRow = change;
                    }
                }
            }
            Assert.isNotNull(householdRow, 'Reported as a household, not as an account');
            Assert.areEqual(Label.Core_Erase_NoteHouseholdKept, householdRow.note, 'Says why');
            Assert.isTrue(
                householdRow.fields.contains(Account.Name.getDescribe().getLabel()),
                'Lists the name it replaced: ' + householdRow.fields
            );
            Assert.isTrue(
                householdRow.fields.contains(
                    Account.Household_Informal_Greeting__c.getDescribe().getLabel()
                ),
                'Lists the greetings it emptied: ' + householdRow.fields
            );
            Assert.isTrue(
                personRow.fields.contains(Label.Core_Erase_Household),
                'The contact account reads as its household: ' + personRow.fields
            );
            Assert.isFalse(
                personRow.fields.contains(Contact.AccountId.getDescribe().getLabel()),
                'Not as the account field: ' + personRow.fields
            );
            String details = [SELECT Details__c FROM Erasure__c WHERE Id = :result.erasureId]
            .Details__c;
            Assert.isTrue(
                details.contains(
                    Label.Core_EraseAction_Cleared + ' | ' + Label.Core_Erase_Household + ' | 1'
                ),
                'The Erasure record uses the same words: ' + details
            );
        }
    }

    /** The row reporting a household the person left that still has members. */
    private static PersonErasure.Change sharedHouseholdRow(
        PersonErasure.Result result,
        Id householdId
    ) {
        for (PersonErasure.Change change : result.changes) {
            if (
                change.objectLabel == Label.Core_Erase_Household &&
                change.action != PersonErasure.CLEARED &&
                change.recordIds.contains(householdId)
            ) {
                return change;
            }
        }
        return null;
    }

    @IsTest
    static void aCustomNamedHouseholdNoLongerNamesTheErasedPerson() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(true);
            addSam(jordan.AccountId);
            update new Account(
                Id = jordan.AccountId,
                Name = 'Jordan and Sam Lee',
                Household_Formal_Greeting__c = 'Mx. Jordan Lee and Mx. Sam Lee',
                Household_Informal_Greeting__c = 'Jordan and Sam',
                Custom_Name__c = true
            );

            PersonErasure.Result preview = PersonErasure.preview(jordan.Id);
            Account untouched = [
                SELECT Name, Custom_Name__c
                FROM Account
                WHERE Id = :jordan.AccountId
            ];
            Assert.areEqual('Jordan and Sam Lee', untouched.Name, 'The preview changes nothing');
            Assert.isTrue(untouched.Custom_Name__c, 'Not even the box');

            PersonErasure.Result result = PersonErasure.erase(jordan.Id, jordan.Name, 'PR-7');

            Account household = [
                SELECT
                    Name,
                    Custom_Name__c,
                    Household_Formal_Greeting__c,
                    Household_Informal_Greeting__c,
                    Member_Count__c
                FROM Account
                WHERE Id = :jordan.AccountId
            ];
            Assert.isFalse(household.Custom_Name__c, 'Custom Name turned off');
            for (
                String wording : new List<String>{
                    household.Name,
                    household.Household_Formal_Greeting__c,
                    household.Household_Informal_Greeting__c
                }
            ) {
                Assert.isFalse(
                    String.valueOf(wording).contains('Jordan'),
                    'The erased person is not named: ' + wording
                );
            }
            Assert.areEqual(
                'Sam',
                household.Household_Informal_Greeting__c,
                'Named from who is left'
            );
            Assert.areEqual(1, household.Member_Count__c, 'Recounted without Jordan');

            for (PersonErasure.Result run : new List<PersonErasure.Result>{ preview, result }) {
                PersonErasure.Change row = sharedHouseholdRow(run, jordan.AccountId);
                Assert.isNotNull(row, 'The household is reported');
                Assert.areEqual(PersonErasure.UPDATED, row.action, 'As updated');
                Assert.areEqual(
                    Label.Core_Erase_NoteCustomNameReleased,
                    row.note,
                    'Saying the typed name was replaced'
                );
                Assert.isTrue(
                    row.fields.contains(Account.Name.getDescribe().getLabel()),
                    'Lists the name: ' + row.fields
                );
                Assert.isTrue(
                    row.fields.contains(Account.Custom_Name__c.getDescribe().getLabel()),
                    'And the box: ' + row.fields
                );
            }
            String details = [SELECT Details__c FROM Erasure__c WHERE Id = :result.erasureId]
            .Details__c;
            Assert.isTrue(
                details.contains(Label.Core_Erase_NoteCustomNameReleased),
                'The Erasure record says the same: ' + details
            );
            Assert.isFalse(details.contains('Jordan'), 'And names nobody');
        }
    }

    @IsTest
    static void aNamedHouseholdListsOnlyTheFieldsThatChanged() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(true);
            addSam(jordan.AccountId);
            String nameBefore = [SELECT Name FROM Account WHERE Id = :jordan.AccountId].Name;

            PersonErasure.Result result = PersonErasure.erase(jordan.Id, jordan.Name, null);

            Account household = [
                SELECT Name, Household_Informal_Greeting__c
                FROM Account
                WHERE Id = :jordan.AccountId
            ];
            Assert.isFalse(
                household.Household_Informal_Greeting__c.contains('Jordan'),
                'Renamed without Jordan: ' + household.Household_Informal_Greeting__c
            );
            PersonErasure.Change row = sharedHouseholdRow(result, jordan.AccountId);
            Assert.areEqual(PersonErasure.UPDATED, row.action, 'Reported as updated');
            Assert.areEqual(Label.Core_Erase_NoteRenamed, row.note, 'Named again by upkeep');
            Assert.isTrue(
                row.fields.contains(Account.Member_Count__c.getDescribe().getLabel()),
                'Lists the count: ' + row.fields
            );
            Assert.isTrue(
                row.fields.contains(
                    Account.Household_Informal_Greeting__c.getDescribe().getLabel()
                ),
                'And the greeting: ' + row.fields
            );
            Assert.areEqual(
                household.Name != nameBefore,
                row.fields.contains(Account.Name.getDescribe().getLabel()),
                'The name is listed only if it changed: ' + nameBefore + ', ' + row.fields
            );
        }
    }

    @IsTest
    static void aContactsOrganizationAccountKeepsItsFieldLabelNotHousehold() {
        System.runAs(eraser()) {
            isolate();
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            HouseholdTestDataFactory.save(settings);
            Account employer = RelationshipTestDataFactory.organizations(1, 'Union')[0];
            Contact jordan = new Contact(
                FirstName = 'Jordan',
                LastName = 'Lee',
                Phone = '555-0100',
                AccountId = employer.Id
            );
            insert jordan;

            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Jordan Lee', null);

            PersonErasure.Change personRow;
            for (PersonErasure.Change change : result.changes) {
                if (
                    change.action == PersonErasure.CLEARED && change.recordIds.contains(jordan.Id)
                ) {
                    personRow = change;
                }
            }
            Assert.isNotNull(personRow, 'The contact is reported');
            Assert.isTrue(
                personRow.fields.contains(Contact.AccountId.getDescribe().getLabel()),
                'An employer reads as the account field: ' + personRow.fields
            );
            Assert.isFalse(
                personRow.fields.contains(Label.Core_Erase_Household),
                'Not as a household: ' + personRow.fields
            );
            String details = [SELECT Details__c FROM Erasure__c WHERE Id = :result.erasureId]
            .Details__c;
            Assert.isFalse(
                details.contains(
                    Label.Core_EraseAction_Cleared + ' | ' + Label.Core_Erase_Household + ' | 1'
                ),
                'The Erasure record does not call it a household: ' + details
            );
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
            // Real person accounts where the org has them: an ordinary account standing in
            // for one there would be refused the person fields the erasure empties.
            Boolean realPeople = OrgShapeDetector.hasPersonAccounts();
            List<Account> people = realPeople
                ? personAccounts(2, 'Okafor')
                : RelationshipTestDataFactory.peopleAsAccounts(2, 'Okafor');
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
            if (!realPeople) {
                // An ordinary account stands in for a person account (RelationshipTestDataFactory).
                PersonRecordSelector.personRecordOverride = true;
            }

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
        // A user who sees Jordan and may not edit him: a user on the running profile would be
        // an administrator, and under private sharing one who cannot see him is told he is not
        // a person.
        System.runAs(TestUsers.peopleReaderWith(
            'Reader',
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
    static void whatAModuleDeletedIsEmptiedFromTheRecycleBinWithTheRest() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(true);
            Contact sam = addSam(jordan.AccountId);
            // A record of Sam's, which Core itself leaves alone, stands in for a module's own.
            Address__c moduleRecord = new Address__c(
                Contact__c = sam.Id,
                Type__c = 'Home',
                City__c = 'Springfield'
            );
            insert moduleRecord;
            PersonErasureExtensions.overrides.add(new DeletesARecord(moduleRecord.Id));

            PersonErasure.erase(jordan.Id, 'Jordan Lee', null);

            Assert.isTrue(
                [SELECT IsDeleted FROM Address__c WHERE Id = :moduleRecord.Id ALL ROWS].IsDeleted,
                'The module deleted its record'
            );
            Assert.isTrue(
                PersonErasure.deletedIds.contains(moduleRecord.Id),
                'The record the module reported as Deleted is emptied from the Recycle Bin'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'PersonErasure.emptyRecycleBin'
                    WITH SYSTEM_MODE
                ],
                'Emptying the Recycle Bin did not fail'
            );
        }
    }

    @IsTest
    static void aFileAModuleDeletesIsNotAlsoListedAsKept() {
        System.runAs(eraser()) {
            isolate();
            Contact jordan = coupleInContactMode(false);
            insert new List<ContentVersion>{
                new ContentVersion(
                    Title = 'Generated letter',
                    PathOnClient = 'letter.txt',
                    VersionData = Blob.valueOf('Dear Jordan'),
                    FirstPublishLocationId = jordan.Id
                ),
                new ContentVersion(
                    Title = 'Photo',
                    PathOnClient = 'photo.txt',
                    VersionData = Blob.valueOf('A photo'),
                    FirstPublishLocationId = jordan.Id
                )
            };
            PersonErasureExtensions.overrides.add(new DeletesGeneratedFiles());

            Assert.areEqual(
                1,
                filesKept(PersonErasure.preview(jordan.Id)),
                'The preview keeps only the file the module leaves'
            );
            Test.startTest();
            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Jordan Lee', null);
            Test.stopTest();
            Assert.areEqual(1, filesKept(result), 'The erasure keeps only the file it left');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM ContentDocument WHERE Title = 'Photo'],
                'The other file is still there'
            );
        }
    }

    private static Integer filesKept(PersonErasure.Result result) {
        Integer count = 0;
        for (PersonErasure.Change change : result.changes) {
            if (
                change.action == PersonErasure.KEPT &&
                change.objectLabel == Label.Core_Erase_Files
            ) {
                count += change.count;
            }
        }
        return count;
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
        Assert.isTrue(
            text.startsWith(Label.Core_EraseAction_Cleared + ' | Contact | 1 | Email, Phone | '),
            'In the words the screen shows: ' + text
        );
    }

    @IsTest
    static void installedModulesAreFoundByNameAfterTheInjectedOnes() {
        System.runAs(eraser()) {
            PersonErasureExtensions.noneForTest = false;
            PersonErasureExtensions.overrides.add(new KeepsDepartment());
            Integer installedModules = 0;
            for (String className : PersonErasureExtensions.EXTENSION_CLASSES) {
                installedModules += Type.forName(className) != null ? 1 : 0;
            }

            List<PersonErasureExtension> found = PersonErasureExtensions.installed();

            Assert.areEqual(
                1 + installedModules,
                found.size(),
                'Each installed module is asked for by name'
            );
            Assert.isTrue(found[0] instanceof KeepsDepartment, 'Injected ones come first');
        }
    }

    @IsTest
    static void aModuleThatDoesNotImplementTheInterfaceRefusesTheErasure() {
        System.runAs(eraser()) {
            PersonErasureExtensions.noneForTest = false;
            PersonErasureExtensions.EXTENSION_CLASSES.add('PersonErasureTest.NotAnExtension');

            Test.startTest();
            try {
                PersonErasureExtensions.installed();
                Assert.fail('An installed module that cannot be used refuses the erasure');
            } catch (PersonErasure.ErasureException refused) {
                Assert.isTrue(
                    refused.getMessage().contains('PersonErasureTest.NotAnExtension'),
                    'Names the module: ' + refused.getMessage()
                );
            }
            Test.stopTest();
            List<Error_Log__c> entries = [
                SELECT Message__c
                FROM Error_Log__c
                WHERE Context__c = 'PersonErasureExtensions.resolve'
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(1, entries.size(), 'The reason is logged');
            Assert.isTrue(
                entries[0].Message__c.contains('does not implement PersonErasureExtension'),
                'It says why: ' + entries[0].Message__c
            );
        }
    }

    @IsTest
    static void aModuleThatCannotBeBuiltRefusesTheErasure() {
        System.runAs(eraser()) {
            PersonErasureExtensions.noneForTest = false;
            PersonErasureExtensions.EXTENSION_CLASSES.add('PersonErasureTest.CannotBuild');

            Test.startTest();
            try {
                PersonErasureExtensions.installed();
                Assert.fail('An installed module that cannot be built refuses the erasure');
            } catch (PersonErasure.ErasureException refused) {
                Assert.isTrue(
                    refused.getMessage().contains('PersonErasureTest.CannotBuild'),
                    'Names the module: ' + refused.getMessage()
                );
            }
            Test.stopTest();
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'PersonErasureExtensions.resolve'
                    WITH SYSTEM_MODE
                ],
                'The reason is logged'
            );
        }
    }

    public class NotAnExtension {
    }

    public class CannotBuild implements PersonErasureExtension {
        public CannotBuild() {
            throw new PersonErasure.ErasureException('No way to build this');
        }
        public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
            return new Set<Schema.SObjectField>();
        }
        public List<PersonErasure.Change> erase(Id personId) {
            return new List<PersonErasure.Change>();
        }
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

    /** A module that deletes one record of its own and reports it, as Volunteers does. */
    private class DeletesARecord implements PersonErasureExtension {
        private Id recordId;
        DeletesARecord(Id recordId) {
            this.recordId = recordId;
        }
        public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
            return new Set<Schema.SObjectField>();
        }
        public List<PersonErasure.Change> erase(Id personId) {
            Database.delete(new List<Id>{ recordId }, true, AccessLevel.USER_MODE);
            return new List<PersonErasure.Change>{
                new PersonErasure.Change(
                    PersonErasure.DELETED,
                    'Module record',
                    new List<Id>{ recordId },
                    null
                )
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

    /** A module that deletes the files it generated for the person, as Volunteers does. */
    private class DeletesGeneratedFiles implements PersonErasureExtension {
        public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
            return new Set<Schema.SObjectField>();
        }
        public List<PersonErasure.Change> erase(Id personId) {
            List<Id> generated = new List<Id>();
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :personId AND ContentDocument.Title = 'Generated letter'
            ]) {
                generated.add(link.ContentDocumentId);
            }
            Database.delete(generated, true, AccessLevel.USER_MODE);
            return new List<PersonErasure.Change>{
                new PersonErasure.Change(PersonErasure.DELETED, 'Module file', generated, null)
            };
        }
    }
}
