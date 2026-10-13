/**
 * The Get Household Summary action (Q-14): a household found by its own id or by a member's,
 * in either membership mode, with its greetings, address and members, the primary member
 * first; anything that is not a household answered in plain words; and a user who cannot
 * read the household's fields refused rather than shown part of it.
 */
@IsTest(testFor='ApexClass:GetHouseholdSummaryAction')
private class GetHouseholdSummaryActionTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void aHouseholdIsSummarizedByItsOwnId() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert household;
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            maria.AccountId = household.Id;
            wei.AccountId = household.Id;
            insert new List<Contact>{ maria, wei };
            update new Account(
                Id = household.Id,
                Primary_Contact__c = wei.Id,
                BillingStreet = '12 Elm Street',
                BillingCity = 'Springfield',
                BillingState = 'IL',
                BillingPostalCode = '62701'
            );

            Test.startTest();
            List<GetHouseholdSummaryAction.Result> results = GetHouseholdSummaryAction.summarize(
                new List<GetHouseholdSummaryAction.Request>{ request(household.Id) }
            );
            Test.stopTest();

            GetHouseholdSummaryAction.Result summary = results[0];
            Assert.isNull(summary.errorMessage, 'The household was found');
            Assert.areEqual(household.Id, summary.householdId);
            Assert.isTrue(String.isNotBlank(summary.name), 'The household is named');
            Assert.areEqual(2, summary.members.size(), 'Both members are listed');
            Assert.areEqual(2, summary.memberCount, 'The member count is kept by Core');
            Assert.isTrue(String.isNotBlank(summary.formalGreeting), 'The greeting is given');
            Assert.areEqual(
                '12 Elm Street, Springfield, IL, 62701',
                summary.mailingAddress,
                'The address is on one line'
            );
            Assert.isTrue(String.isNotBlank(summary.primaryContactName), 'The primary is named');
            Assert.isTrue(summary.members[0].isPrimary, 'The primary member is listed first');
        }
    }

    @IsTest
    static void aPersonIdSummarizesTheirHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id householdId = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;

            Test.startTest();
            List<GetHouseholdSummaryAction.Result> results = GetHouseholdSummaryAction.summarize(
                new List<GetHouseholdSummaryAction.Request>{ request(maria.Id) }
            );
            Test.stopTest();

            Assert.areEqual(householdId, results[0].householdId, 'Her household is summarized');
            Assert.areEqual(1, results[0].members.size());
            Assert.areEqual(maria.Id, results[0].members[0].personId);
            Assert.areEqual('Maria Garcia', results[0].members[0].name);
        }
    }

    @IsTest
    static void aMembershipFindsTheHouseholdInTheFlexibleWay() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert household;
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert wei;
            insert new Household_Member__c(
                Household__c = household.Id,
                Contact__c = wei.Id,
                Role__c = 'Head',
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            );

            Test.startTest();
            List<GetHouseholdSummaryAction.Result> results = GetHouseholdSummaryAction.summarize(
                new List<GetHouseholdSummaryAction.Request>{ request(wei.Id) }
            );
            Test.stopTest();

            Assert.areEqual(household.Id, results[0].householdId);
            Assert.areEqual(1, results[0].members.size(), 'Wei is the member');
            Assert.isTrue(results[0].members[0].isPrimary, 'and the primary one');
        }
    }

    @IsTest
    static void anythingElseIsAnsweredInPlainWords() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account organization = new Account(Name = 'The Union Foundation');
            insert organization;
            Contact loner = HouseholdTestDataFactory.newContact('Ms.', 'Ada', 'Stone');
            insert loner;

            Test.startTest();
            List<GetHouseholdSummaryAction.Result> results = GetHouseholdSummaryAction.summarize(
                new List<GetHouseholdSummaryAction.Request>{
                    request(organization.Id),
                    request(loner.Id),
                    request('not an id'),
                    null
                }
            );
            Test.stopTest();

            Assert.areEqual(4, results.size(), 'Every request is answered');
            Assert.areEqual(Label.Core_AgentActions_HouseholdNotFound, results[0].errorMessage);
            Assert.areEqual(Label.Core_AgentActions_PersonHasNoHousehold, results[1].errorMessage);
            Assert.areEqual(Label.Core_AgentActions_HouseholdNotFound, results[2].errorMessage);
            Assert.areEqual(Label.Core_AgentActions_HouseholdNotFound, results[3].errorMessage);
        }
    }

    @IsTest
    static void twoHundredPeopleAreSummarizedInOrder() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');
            insert people;
            List<GetHouseholdSummaryAction.Request> requests = new List<GetHouseholdSummaryAction.Request>();
            for (Contact person : people) {
                requests.add(request(person.Id));
            }

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            List<GetHouseholdSummaryAction.Result> results = GetHouseholdSummaryAction.summarize(
                requests
            );
            Integer queriesUsed = Limits.getQueries() - queriesBefore;
            Test.stopTest();

            Assert.areEqual(200, results.size());
            for (Integer i = 0; i < 200; i++) {
                Assert.isNull(results[i].errorMessage, 'Person ' + i + ' has a household');
                Assert.areEqual(
                    people[i].Id,
                    results[i].members[0].personId,
                    'Request ' + i + ' is answered in its own position'
                );
            }
            Assert.isTrue(queriesUsed <= 10, 'The requests share their queries: ' + queriesUsed);
        }
    }

    @IsTest
    static void aUserWhoCannotReadHouseholdFieldsIsToldSo() {
        Account household;
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert household;
        }
        User outsider = HouseholdTestDataFactory.standardUser('summary');
        List<GetHouseholdSummaryAction.Result> results;

        Test.startTest();
        System.runAs(outsider) {
            results = GetHouseholdSummaryAction.summarize(
                new List<GetHouseholdSummaryAction.Request>{ request(household.Id) }
            );
        }
        Test.stopTest();

        Assert.areEqual(Label.Core_AgentActions_NoAccess, results[0].errorMessage);
        Assert.isNull(results[0].householdId, 'Nothing of the household is shown');
        Assert.isTrue(results[0].members.isEmpty(), 'No member is shown');
    }

    private static GetHouseholdSummaryAction.Request request(String recordId) {
        GetHouseholdSummaryAction.Request result = new GetHouseholdSummaryAction.Request();
        result.recordId = recordId;
        return result;
    }
}
