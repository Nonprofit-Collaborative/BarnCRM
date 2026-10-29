/**
 * Which scheduled payment a gift typed on a gift entry screen can pay (canonical model R-DM8):
 * the donor's open payments, the suggestion under the org's matching window and tolerance, and
 * the check of a choice at save. Run as Maria, who holds the admin permission sets, because
 * the payments are read in her own mode.
 */
@IsTest(testFor='ApexClass:GiftEntryPayments')
private class GiftEntryPaymentsTest {
    @TestSetup
    static void createTestUser() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.createUser(
                'Maria',
                new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
            );
        }
    }

    /** Maria, built by the setup, found by the username TestUsers gives her last name. */
    private static User maria() {
        return [
            SELECT Id
            FROM User
            WHERE Username LIKE 'barn-test.maria.%' AND LastName = 'Maria'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    /**
     * An active pledge of this donor with a payment due on each of these days of March, owned by
     * Maria: commitments are private and Giving Admin has no View All on them, so she sees the
     * pledges she owns.
     */
    private static List<Installment__c> pledge(Id personId, Map<Integer, Decimal> dueDays) {
        Commitment__c pledge = new Commitment__c(
            OwnerId = maria().Id,
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = personId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.newInstance(2026, 1, 1),
            Expected_Total__c = 1200,
            Installments_Planned__c = 12
        );
        insert pledge;
        // The schedule the pledge generates is replaced by the payments the test names.
        delete [SELECT Id FROM Installment__c WHERE Commitment__c = :pledge.Id WITH SYSTEM_MODE];
        List<Installment__c> payments = new List<Installment__c>();
        Integer sequence = 1;
        for (Integer day : dueDays.keySet()) {
            payments.add(
                new Installment__c(
                    Commitment__c = pledge.Id,
                    Sequence__c = sequence++,
                    Due_Date__c = Date.newInstance(2026, 3, day),
                    Expected_Amount__c = dueDays.get(day),
                    Status__c = 'Scheduled'
                )
            );
        }
        insert payments;
        return [
            SELECT Id, Name, Due_Date__c, Commitment__c
            FROM Installment__c
            WHERE Id IN :payments
            WITH SYSTEM_MODE
            ORDER BY Due_Date__c
        ];
    }

    /** A gift from this person of this amount on 15 March. */
    private static GiftEntryPayments.Request request(String key, Id personId, Decimal amount) {
        return new GiftEntryPayments.Request(
            key,
            personId,
            null,
            Date.newInstance(2026, 3, 15),
            amount
        );
    }

    private static GiftEntryPayments.Choices choicesFor(GiftEntryPayments.Request request) {
        GiftEntryPayments.Choices choices;
        System.runAs(maria()) {
            choices = GiftEntryPayments.forRequests(new List<GiftEntryPayments.Request>{ request })
                .get(request.key);
        }
        return choices;
    }

    @IsTest
    static void theOnlyMatchingPaymentIsSuggestedAndChosen() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            List<Installment__c> payments = pledge(
                ana.Id,
                new Map<Integer, Decimal>{ 1 => 100, 15 => 100, 16 => 50 }
            );

            GiftEntryPayments.Choices choices = choicesFor(request('one', ana.Id, 100));

            Assert.areEqual(3, choices.choices.size(), 'Every open payment of Ana is offered.');
            Assert.areEqual(1, choices.suggestedCount, 'Only the 15 March payment of 100 matches.');
            Assert.areEqual(payments[1].Id, choices.suggestedId, 'The only match is chosen.');
            Assert.areEqual(
                payments[0].Id,
                choices.choices[0].value,
                'Earliest due first, not the suggestion first.'
            );
            Assert.isTrue(choices.choices[1].suggested, 'The match is marked.');
            Assert.isFalse(choices.choices[0].suggested, '1 March is outside the 7 day window.');
            Assert.isFalse(choices.choices[2].suggested, '50 is not 100 at a tolerance of zero.');
            Assert.isTrue(
                choices.choices[1].label.contains('100.00'),
                'The label names the expected amount: ' + choices.choices[1].label
            );
        }
    }

    @IsTest
    static void twoMatchingPaymentsAreSuggestedButNeitherIsChosen() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            pledge(ana.Id, new Map<Integer, Decimal>{ 13 => 100, 17 => 100 });

            GiftEntryPayments.Choices choices = choicesFor(request('two', ana.Id, 100));

            Assert.areEqual(2, choices.suggestedCount, 'Both are within the window.');
            Assert.isNull(choices.suggestedId, 'A person chooses between two; nothing is chosen.');
        }
    }

    @IsTest
    static void aPaymentOfSomeoneInTheHouseholdIsOfferedAndAStrangersIsNot() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            Contact ben = new Contact(
                FirstName = 'Ben',
                LastName = 'Ramirez',
                AccountId = ana.AccountId
            );
            insert ben;
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 15 => 100 });
            Contact stranger = GivingTestDataFactory.insertHouseholdContact('Lee', 'Kim', 'Lee');

            GiftEntryPayments.Choices forBen = choicesFor(request('ben', ben.Id, 100));
            GiftEntryPayments.Choices forKim = choicesFor(request('kim', stranger.Id, 100));

            Assert.areEqual(
                payments[0].Id,
                forBen.suggestedId,
                'Ben pays Ana\'s household pledge.'
            );
            Assert.isTrue(forKim.choices.isEmpty(), 'Another household owes nothing of Ana\'s.');
        }
    }

    @IsTest
    static void noDonorMeansNoPayments() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            pledge(ana.Id, new Map<Integer, Decimal>{ 15 => 100 });

            GiftEntryPayments.Choices choices = choicesFor(request('nobody', null, 100));

            Assert.isTrue(choices.choices.isEmpty(), 'No donor, nothing to pay.');
            Assert.isNull(choices.suggestedId, 'Nothing is chosen.');
        }
    }

    @IsTest
    static void aPaymentOnACancelledPledgeIsNeitherOfferedNorConfirmed() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 15 => 100 });
            update new Commitment__c(Id = payments[0].Commitment__c, Status__c = 'Cancelled');

            GiftEntryPayments.Choices choices = choicesFor(request('gone', ana.Id, 100));
            Map<String, Installment__c> confirmed;
            System.runAs(maria()) {
                confirmed = GiftEntryPayments.confirm(
                    new List<GiftEntryPayments.Request>{ request('gone', ana.Id, 100) },
                    new Map<String, Id>{ 'gone' => payments[0].Id }
                );
            }

            Assert.isTrue(choices.choices.isEmpty(), 'A cancelled pledge is owed nothing.');
            Assert.isFalse(confirmed.containsKey('gone'), 'Its payment cannot be paid.');
        }
    }

    @IsTest
    static void confirmKeepsTheDonorsOwnPaymentAndRefusesSomeoneElses() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            Contact kim = GivingTestDataFactory.insertHouseholdContact('Lee', 'Kim', 'Lee');
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 15 => 100 });

            Map<String, Installment__c> confirmed;
            System.runAs(maria()) {
                confirmed = GiftEntryPayments.confirm(
                    new List<GiftEntryPayments.Request>{
                        request('ana', ana.Id, 100),
                        request('kim', kim.Id, 100)
                    },
                    new Map<String, Id>{ 'ana' => payments[0].Id, 'kim' => payments[0].Id }
                );
            }

            Assert.areEqual(payments[0].Id, confirmed.get('ana').Id, 'Ana may pay her own.');
            Assert.areEqual(
                payments[0].Commitment__c,
                confirmed.get('ana').Commitment__c,
                'The pledge comes with it.'
            );
            Assert.isFalse(confirmed.containsKey('kim'), 'Kim may not pay Ana\'s pledge.');
        }
    }

    /** A batch asks for two hundred gifts at once: one query, each gift its own answer. */
    @IsTest
    static void twoHundredRequestsAreAnsweredTogether() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            Contact kim = GivingTestDataFactory.insertHouseholdContact('Lee', 'Kim', 'Lee');
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 15 => 100 });
            List<GiftEntryPayments.Request> requests = new List<GiftEntryPayments.Request>();
            for (Integer index = 0; index < 200; index++) {
                Id donor = Math.mod(index, 2) == 0 ? ana.Id : kim.Id;
                requests.add(request('line' + index, donor, 100));
            }

            Map<String, GiftEntryPayments.Choices> answers;
            Integer queriesBefore;
            Integer queriesUsed;
            System.runAs(maria()) {
                Test.startTest();
                queriesBefore = Limits.getQueries();
                answers = GiftEntryPayments.forRequests(requests);
                queriesUsed = Limits.getQueries() - queriesBefore;
                Test.stopTest();
            }

            Assert.areEqual(200, answers.size(), 'Every line is answered.');
            Assert.areEqual(payments[0].Id, answers.get('line0').suggestedId, 'Ana\'s line is.');
            Assert.isTrue(answers.get('line1').choices.isEmpty(), 'Kim\'s line owes nothing.');
            Assert.isTrue(queriesUsed < 10, 'The lines share their queries: ' + queriesUsed);
        }
    }
}
