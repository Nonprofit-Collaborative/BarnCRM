/**
 * The Create Person action (Q-14): a new person with a household of their own, or added to
 * one that exists in either membership mode without a second household being made for them;
 * a request that cannot be saved answered in plain words while the others are saved; and a
 * user without the access a person needs refused with nothing created.
 */
@IsTest(testFor='ApexClass:CreatePersonAction')
private class CreatePersonActionTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void aPersonWithNoHouseholdNamedGetsOneOfTheirOwn() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

            Test.startTest();
            List<CreatePersonAction.Result> results = CreatePersonAction.create(
                new List<CreatePersonAction.Request>{
                    request('Maria', 'Garcia', 'maria.garcia@example.org', null)
                }
            );
            Test.stopTest();

            Assert.isNull(results[0].errorMessage, 'Maria was created');
            Contact maria = [
                SELECT Id, FirstName, Email, AccountId
                FROM Contact
                WHERE Id = :results[0].personId
            ];
            Assert.areEqual('Maria', maria.FirstName);
            Assert.areEqual('maria.garcia@example.org', maria.Email);
            Assert.isNotNull(maria.AccountId, 'Core gave her a household');
            Assert.areEqual(maria.AccountId, results[0].householdId, 'Her household is given');
        }
    }

    @IsTest
    static void aPersonJoinsTheHouseholdNamedInTheSimpleWay() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(household, AccessLevel.SYSTEM_MODE);
            Integer householdsBefore = [SELECT COUNT() FROM Account];

            Test.startTest();
            List<CreatePersonAction.Result> results = CreatePersonAction.create(
                new List<CreatePersonAction.Request>{
                    request('Luis', 'Garcia', null, household.Id)
                }
            );
            Test.stopTest();

            Assert.isNull(results[0].errorMessage, 'Luis was created');
            Assert.areEqual(household.Id, results[0].householdId);
            Assert.areEqual(
                household.Id,
                [SELECT AccountId FROM Contact WHERE Id = :results[0].personId].AccountId,
                'He points at the household'
            );
            Assert.areEqual(
                householdsBefore,
                [SELECT COUNT() FROM Account],
                'No household of his own was made'
            );
            Assert.areEqual(
                1,
                [SELECT Member_Count__c FROM Account WHERE Id = :household.Id]
                    .Member_Count__c.intValue(),
                'The household counts him'
            );
        }
    }

    @IsTest
    static void aPersonJoinsTheHouseholdNamedInTheFlexibleWay() {
        System.runAs(TestUsers.admin()) {
            // Automatic households on, so a second household for him would show.
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account household = HouseholdTestDataFactory.newHousehold('The Lee Family');
            Database.insert(household, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            List<CreatePersonAction.Result> results = CreatePersonAction.create(
                new List<CreatePersonAction.Request>{ request('Wei', 'Lee', null, household.Id) }
            );
            Test.stopTest();

            Assert.isNull(results[0].errorMessage, 'Wei was created');
            Id weiId = results[0].personId;
            List<Household_Member__c> memberships = [
                SELECT Household__c
                FROM Household_Member__c
                WHERE Contact__c = :weiId
            ];
            Assert.areEqual(1, memberships.size(), 'Wei belongs to one household only');
            Assert.areEqual(household.Id, memberships[0].Household__c, 'the one named');
            Assert.areEqual(household.Id, results[0].householdId);
        }
    }

    @IsTest
    static void aRequestThatCannotBeSavedIsAnsweredAndTheOthersAreSaved() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account organization = new Account(Name = 'The Union Foundation');
            insert organization;

            Test.startTest();
            List<CreatePersonAction.Result> results = CreatePersonAction.create(
                new List<CreatePersonAction.Request>{
                    request('Ada', null, null, null),
                    request('Ada', 'Stone', null, organization.Id),
                    request('Ada', 'Stone', null, 'not an id'),
                    request('Ada', 'Stone', null, null),
                    null
                }
            );
            Test.stopTest();

            Assert.areEqual(5, results.size(), 'Every request is answered');
            Assert.areEqual(
                Label.Core_HouseholdPanel_AddMemberMissingName,
                results[0].errorMessage
            );
            Assert.areEqual(Label.Core_Households_ErrorNotAHousehold, results[1].errorMessage);
            Assert.areEqual(Label.Core_Households_ErrorNotAHousehold, results[2].errorMessage);
            Assert.isNull(results[3].errorMessage, 'The good request was saved');
            Assert.isNotNull(results[3].personId);
            Assert.areEqual(
                Label.Core_HouseholdPanel_AddMemberMissingName,
                results[4].errorMessage
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'Only Ada was created, once');
        }
    }

    @IsTest
    static void twoHundredPeopleAreCreatedInOnePass() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Bulk Family');
            Database.insert(household, AccessLevel.SYSTEM_MODE);
            List<CreatePersonAction.Request> requests = new List<CreatePersonAction.Request>();
            for (Integer i = 0; i < 200; i++) {
                // Half join the household, half get one of their own.
                requests.add(
                    request(
                        'Person' + i,
                        'Bulk' + i,
                        null,
                        Math.mod(i, 2) == 0 ? household.Id : null
                    )
                );
            }

            Test.startTest();
            List<CreatePersonAction.Result> results = CreatePersonAction.create(requests);
            Test.stopTest();

            Assert.areEqual(200, results.size());
            for (Integer i = 0; i < 200; i++) {
                Assert.isNull(results[i].errorMessage, 'Person ' + i + ' was created');
                Assert.isNotNull(results[i].householdId, 'Person ' + i + ' has a household');
                if (Math.mod(i, 2) == 0) {
                    Assert.areEqual(household.Id, results[i].householdId);
                }
            }
            Assert.areEqual(
                100,
                [SELECT COUNT() FROM Contact WHERE AccountId = :household.Id],
                'Half joined the household named'
            );
        }
    }

    @IsTest
    static void aUserWhoCannotEditTheHouseholdIsRefused() {
        Account household;
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(household, AccessLevel.SYSTEM_MODE);
        }
        User reader = readOnlyUser();
        List<CreatePersonAction.Result> results;

        Test.startTest();
        System.runAs(reader) {
            results = CreatePersonAction.create(
                new List<CreatePersonAction.Request>{
                    request('Luis', 'Garcia', null, household.Id)
                }
            );
        }
        Test.stopTest();

        System.runAs(TestUsers.admin()) {
            Assert.isNull(results[0].personId, 'Nobody was created');
            Assert.isNotNull(results[0].errorMessage, 'The user is told why');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Nothing was saved');
        }
    }

    @IsTest
    static void aUserWhoCannotCreatePeopleIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        }
        User reader = readOnlyUser();
        List<CreatePersonAction.Result> results;

        Test.startTest();
        System.runAs(reader) {
            results = CreatePersonAction.create(
                new List<CreatePersonAction.Request>{ request('Luis', 'Garcia', null, null) }
            );
        }
        Test.stopTest();

        System.runAs(TestUsers.admin()) {
            Assert.isNull(results[0].personId, 'Nobody was created');
            Assert.isNotNull(results[0].errorMessage, 'The user is told why');
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Nothing was saved');
        }
    }

    // ------------------------------------------------------------------ helpers

    private static CreatePersonAction.Request request(
        String firstName,
        String lastName,
        String email,
        String householdId
    ) {
        CreatePersonAction.Request result = new CreatePersonAction.Request();
        result.firstName = firstName;
        result.lastName = lastName;
        result.email = email;
        result.householdId = householdId;
        return result;
    }

    /**
     * A user who can read households and people but create or edit neither: the Read Only
     * standard profile, or Minimum Access where an org has no Read Only profile.
     */
    private static User readOnlyUser() {
        Id profileId = TestUsers.readOnlyProfileId();
        String unique = 'barnperson' + Datetime.now().getTime();
        User result = new User(
            ProfileId = profileId,
            LastName = 'Reader',
            Alias = 'reader',
            Email = unique + '@barncrm.test.invalid',
            Username = unique + '@barncrm.test.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert result;
        }
        return result;
    }
}
