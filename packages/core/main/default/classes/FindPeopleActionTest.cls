/**
 * The Find People action (Q-14): people found by name or exact email with the household each
 * belongs to, in either membership mode, every search answered in its own position, and a
 * user who cannot read people answered with a plain refusal rather than a failure.
 */
@IsTest(testFor='ApexClass:FindPeopleAction')
private class FindPeopleActionTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void aNameFindsThePersonAndTheirHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            maria.Email = 'maria.garcia@example.org';
            insert maria;
            Id householdId = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;

            Test.startTest();
            List<FindPeopleAction.Result> results = FindPeopleAction.find(
                new List<FindPeopleAction.Request>{ request('garc') }
            );
            Test.stopTest();

            Assert.areEqual(1, results.size(), 'One answer per search');
            Assert.isNull(results[0].errorMessage, 'The search ran');
            Assert.areEqual(1, results[0].matches.size(), 'Maria is found by part of her name');
            FindPeopleAction.PersonMatch match = results[0].matches[0];
            Assert.areEqual(maria.Id, match.personId, 'The contact is the person');
            Assert.areEqual('maria.garcia@example.org', match.email, 'Her email is given');
            Assert.areEqual(householdId, match.householdId, 'Her household is given');
            Assert.isTrue(String.isNotBlank(match.householdName), 'Her household is named');
        }
    }

    @IsTest
    static void anEmailMatchesExactlyIgnoringCase() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            maria.Email = 'maria.garcia@example.org';
            Contact other = HouseholdTestDataFactory.newContact('Mr.', 'Mario', 'Garcia');
            other.Email = 'mario.garcia@example.org';
            insert new List<Contact>{ maria, other };

            Test.startTest();
            List<FindPeopleAction.Result> results = FindPeopleAction.find(
                new List<FindPeopleAction.Request>{
                    request(' Maria.Garcia@Example.org '),
                    request('nobody@example.org')
                }
            );
            Test.stopTest();

            Assert.areEqual(1, results[0].matches.size(), 'Only the exact address matches');
            Assert.areEqual(maria.Id, results[0].matches[0].personId, 'It is Maria');
            Assert.isTrue(results[1].matches.isEmpty(), 'An unknown address finds nobody');
            Assert.isNull(results[1].errorMessage, 'Finding nobody is not an error');
        }
    }

    @IsTest
    static void aMembershipGivesTheHouseholdInTheFlexibleWay() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert household;
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert wei;
            insert new Household_Member__c(
                Household__c = household.Id,
                Contact__c = wei.Id,
                Is_Primary__c = true,
                Start_Date__c = Date.today()
            );

            Test.startTest();
            List<FindPeopleAction.Result> results = FindPeopleAction.find(
                new List<FindPeopleAction.Request>{ request('Wei Lee') }
            );
            Test.stopTest();

            Assert.areEqual(1, results[0].matches.size(), 'Wei is found');
            Assert.areEqual(
                household.Id,
                results[0].matches[0].householdId,
                'His household comes from his membership'
            );
            Assert.areEqual('The Lee Family', results[0].matches[0].householdName);
        }
    }

    @IsTest
    static void aShortSearchIsRefusedAndTheOthersStillRun() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            insert HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');

            Test.startTest();
            List<FindPeopleAction.Result> results = FindPeopleAction.find(
                new List<FindPeopleAction.Request>{ request('G'), request('Garcia'), null }
            );
            Test.stopTest();

            Assert.areEqual(3, results.size(), 'Every search is answered');
            Assert.areEqual(Label.Core_AgentActions_SearchTooShort, results[0].errorMessage);
            Assert.areEqual(1, results[1].matches.size(), 'The good search still ran');
            Assert.areEqual(Label.Core_AgentActions_SearchTooShort, results[2].errorMessage);
        }
    }

    @IsTest
    static void maximumResultsCapsTheMatches() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            insert HouseholdTestDataFactory.manyContacts(30, 'Okafor');
            FindPeopleAction.Request three = request('Okafor');
            three.maxResults = 3;
            FindPeopleAction.Request tooMany = request('Okafor');
            tooMany.maxResults = 500;

            Test.startTest();
            List<FindPeopleAction.Result> results = FindPeopleAction.find(
                new List<FindPeopleAction.Request>{ three, tooMany, request('Okafor') }
            );
            Test.stopTest();

            Assert.areEqual(3, results[0].matches.size(), 'Three were asked for');
            Assert.areEqual(25, results[1].matches.size(), 'Never more than 25');
            Assert.areEqual(10, results[2].matches.size(), 'Ten when not said');
        }
    }

    @IsTest
    static void twoHundredSearchesAreAnsweredInOrderFromOneQuery() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Contact> people = HouseholdTestDataFactory.manyContacts(200, 'Bulk');
            insert people;
            List<FindPeopleAction.Request> requests = new List<FindPeopleAction.Request>();
            for (Integer i = 0; i < 200; i++) {
                requests.add(request('Person' + i + ' Bulk' + i));
            }

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            List<FindPeopleAction.Result> results = FindPeopleAction.find(requests);
            Integer queriesUsed = Limits.getQueries() - queriesBefore;
            Test.stopTest();

            Assert.areEqual(200, results.size(), 'Every search is answered');
            for (Integer i = 0; i < 200; i++) {
                Assert.areEqual(1, results[i].matches.size(), 'Search ' + i + ' finds one');
                Assert.areEqual(
                    people[i].Id,
                    results[i].matches[0].personId,
                    'Search ' + i + ' is answered in its own position'
                );
            }
            Assert.isTrue(queriesUsed <= 5, 'The searches share their queries: ' + queriesUsed);
        }
    }

    @IsTest
    static void aUserWhoCannotReadPeopleIsToldSo() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            insert HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
        }
        User restricted = minimumAccessUser();
        List<FindPeopleAction.Result> results;

        Test.startTest();
        System.runAs(restricted) {
            results = FindPeopleAction.find(
                new List<FindPeopleAction.Request>{ request('Garcia') }
            );
        }
        Test.stopTest();

        Assert.areEqual(Label.Core_AgentActions_NoAccess, results[0].errorMessage);
        Assert.isTrue(results[0].matches.isEmpty(), 'Nobody is returned');
    }

    // ------------------------------------------------------------------ helpers

    private static FindPeopleAction.Request request(String searchText) {
        FindPeopleAction.Request result = new FindPeopleAction.Request();
        result.searchText = searchText;
        return result;
    }

    /** A user on the profile with no object access at all, so reading contacts is refused. */
    private static User minimumAccessUser() {
        List<Profile> minimal = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        Assert.isFalse(minimal.isEmpty(), 'Every org has the Minimum Access profile');
        String unique = 'barnfind' + Datetime.now().getTime();
        User result = new User(
            ProfileId = minimal[0].Id,
            LastName = 'Restricted',
            Alias = 'restrict',
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
