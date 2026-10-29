/**
 * ADR-0032's second test: the ledger is the guard (R-AK6, R-AK7, R-AK9, R-AK10).
 *
 * Nothing here sends mail. The sender is a stand-in that records what it was handed and answers
 * however the test says, which is the only way to prove what the feature records after a partial
 * failure.
 */
@IsTest(testFor='ApexClass:AcknowledgmentService, ApexClass:AcknowledgmentRuleService')
private class AcknowledgmentSendTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
        }
    }

    private static Acknowledgment_Rule__c emailRule() {
        Acknowledgment_Rule__c rule = AcknowledgmentTestData.buildRule(
            'Everything else',
            100,
            AcknowledgmentRuleService.CHANNEL_EMAIL,
            'BarnCRM_Thank_You'
        );
        insert rule;
        return rule;
    }

    private static List<Gift__c> queuedGiftsInMemory(List<Id> giftIds) {
        return [
            SELECT
                Id,
                Name,
                Amount__c,
                Gift_Date__c,
                Type__c,
                Status__c,
                Appeal__c,
                Acknowledgment_Status__c,
                Donor_Contact__c,
                Donor_Account__c,
                Donor_Account__r.Primary_Contact__c
            FROM Gift__c
            WHERE Id IN :giftIds
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void aSavedGiftJoinsTheQueueAndAnUnmatchedOneDoesNot() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            Acknowledgment_Rule__c rule = emailRule();
            rule.Minimum_Amount__c = 100;
            update rule;
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');

            Gift__c matched = GivingTestDataFactory.buildGift(donor.Id, 250);
            Gift__c unmatched = GivingTestDataFactory.buildGift(donor.Id, 25);
            Gift__c pending = GivingTestDataFactory.buildGift(donor.Id, 500);
            pending.Status__c = 'Pending';

            Test.startTest();
            insert new List<Gift__c>{ matched, unmatched, pending };
            Test.stopTest();

            Map<Id, Gift__c> saved = new Map<Id, Gift__c>(
                [
                    SELECT Id, Acknowledgment_Status__c
                    FROM Gift__c
                    WHERE Id IN :new List<Id>{ matched.Id, unmatched.Id, pending.Id }
                ]
            );
            Assert.areEqual(
                AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE,
                saved.get(matched.Id).Acknowledgment_Status__c,
                'A 250 gift matches the rule from 100 up, so it is waiting to be thanked for.'
            );
            Assert.areEqual(
                AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE,
                saved.get(unmatched.Id).Acknowledgment_Status__c,
                'A 25 gift matches no rule, so the package has no opinion and leaves the status the ' +
                'gift was saved with (R-AK1).'
            );
            Assert.areEqual(
                AcknowledgmentRuleService.STATUS_NOT_REQUIRED,
                saved.get(pending.Id).Acknowledgment_Status__c,
                'A pending gift leaves the queue rather than sitting in it until somebody notices ' +
                '(R-AK8).'
            );
        }
    }

    @IsTest
    static void aChannelNoneRuleTakesGiftsOutOfTheQueue() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            Acknowledgment_Rule__c silent = AcknowledgmentTestData.buildRule(
                'Staff campaign',
                10,
                AcknowledgmentRuleService.CHANNEL_NONE,
                null
            );
            insert silent;
            Contact donor = AcknowledgmentTestData.insertDonor(
                'Grace',
                'Hopper',
                'grace@example.org'
            );

            Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 40);
            insert gift;

            Assert.areEqual(
                AcknowledgmentRuleService.STATUS_NOT_REQUIRED,
                [SELECT Acknowledgment_Status__c FROM Gift__c WHERE Id = :gift.Id]
                .Acknowledgment_Status__c,
                'A rule whose channel is None is the organization saying this kind of gift does not ' +
                'get a thank you, which is Not required rather than Do not acknowledge (R-AK4).'
            );
        }
    }

    @IsTest
    static void aPersonsDoNotAcknowledgeIsNeverOverwritten() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();
            Contact donor = AcknowledgmentTestData.insertDonor(
                'Alan',
                'Turing',
                'alan@example.org'
            );

            Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 500);
            gift.Acknowledgment_Status__c = AcknowledgmentRuleService.STATUS_DO_NOT_ACKNOWLEDGE;
            insert gift;
            gift.Amount__c = 600;
            update gift;

            Assert.areEqual(
                AcknowledgmentRuleService.STATUS_DO_NOT_ACKNOWLEDGE,
                [SELECT Acknowledgment_Status__c FROM Gift__c WHERE Id = :gift.Id]
                .Acknowledgment_Status__c,
                'Do not acknowledge is a persons instruction about one gift, and editing the gift ' +
                'does not undo it (R-AK6).'
            );
        }
    }

    @IsTest
    static void aSendRecordsWhatWentAndStampsTheGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();
            Contact donor = AcknowledgmentTestData.insertDonor(
                'Ada',
                'Lovelace',
                'ada@example.org'
            );
            Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 250);
            insert gift;

            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            AcknowledgmentService.senderOverride = sender;

            Test.startTest();
            AcknowledgmentService.SendCounts counts = AcknowledgmentService.sendEmails(
                queuedGiftsInMemory(new List<Id>{ gift.Id }),
                null
            );
            Test.stopTest();

            Assert.areEqual(1, counts.sent, 'One gift was waiting and one thank you went out.');
            Assert.areEqual(1, sender.received.size(), 'One message reached the platform.');

            List<Acknowledgment__c> rows = [
                SELECT
                    Status__c,
                    Channel__c,
                    Template__c,
                    Recipient_Email__c,
                    Gift_Key__c,
                    Sent_On__c
                FROM Acknowledgment__c
                WHERE Gift__c = :gift.Id
            ];
            Assert.areEqual(1, rows.size(), 'One thank you produces one row, not two.');
            Assert.areEqual(
                AcknowledgmentService.STATUS_SENT,
                rows[0].Status__c,
                'The row says it went.'
            );
            Assert.areEqual(
                'BarnCRM_Thank_You',
                rows[0].Template__c,
                'The row keeps the template that was used, because the template will be rewritten ' +
                'and the question later is which letter this donor got.'
            );
            Assert.areEqual(
                'ada@example.org',
                rows[0].Recipient_Email__c,
                'And the address it actually went to, because a contacts address changes.'
            );
            Assert.areEqual(
                String.valueOf(gift.Id),
                rows[0].Gift_Key__c,
                'The claim key stands, which is what stops a second thank you (R-AK7).'
            );
            Assert.areEqual(
                AcknowledgmentRuleService.STATUS_ACKNOWLEDGED,
                [SELECT Acknowledgment_Status__c FROM Gift__c WHERE Id = :gift.Id]
                .Acknowledgment_Status__c,
                'The gifts summary is written from the ledger (R-AK6).'
            );
        }
    }

    @IsTest
    static void aSecondSendOverTheSameQueueSendsNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();
            Contact donor = AcknowledgmentTestData.insertDonor(
                'Ada',
                'Lovelace',
                'ada@example.org'
            );
            Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 250);
            insert gift;

            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            AcknowledgmentService.senderOverride = sender;
            List<Gift__c> queue = queuedGiftsInMemory(new List<Id>{ gift.Id });

            Test.startTest();
            AcknowledgmentService.sendEmails(queue, null);
            AcknowledgmentService.SendCounts second = AcknowledgmentService.sendEmails(queue, null);
            Test.stopTest();

            Assert.areEqual(
                0,
                second.sent,
                'The second run over the same gift sends nothing: the claim key is held (R-AK7).'
            );
            Assert.areEqual(
                1,
                sender.received.size(),
                'And the platform was handed one message in total, not two.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Acknowledgment__c WHERE Gift__c = :gift.Id],
                'One row, because the unique key refused the second one.'
            );
        }
    }

    @IsTest
    static void oneFailedSendDoesNotStopTheOthers() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();
            Contact first = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            Contact second = AcknowledgmentTestData.insertDonor(
                'Alan',
                'Turing',
                'alan@example.org'
            );
            Gift__c good = GivingTestDataFactory.buildGift(first.Id, 100);
            Gift__c bad = GivingTestDataFactory.buildGift(second.Id, 200);
            insert new List<Gift__c>{ good, bad };

            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            sender.failAt.add(1);
            sender.failureReason = 'The address bounced.';
            AcknowledgmentService.senderOverride = sender;

            Test.startTest();
            AcknowledgmentService.SendCounts counts = AcknowledgmentService.sendEmails(
                queuedGiftsInMemory(new List<Id>{ good.Id, bad.Id }),
                null
            );
            Test.stopTest();

            Assert.areEqual(1, counts.sent, 'The first thank you went.');
            Assert.areEqual(1, counts.errors, 'The second did not, and is counted.');

            Map<Id, Acknowledgment__c> byGift = new Map<Id, Acknowledgment__c>();
            for (Acknowledgment__c row : [
                SELECT Gift__c, Status__c, Failure_Reason__c, Gift_Key__c
                FROM Acknowledgment__c
            ]) {
                byGift.put(row.Gift__c, row);
            }
            Assert.areEqual(
                AcknowledgmentService.STATUS_SENT,
                byGift.get(good.Id).Status__c,
                'A neighbour failing does not stop a thank you that was fine (R-AK10).'
            );
            Assert.areEqual(
                'The address bounced.',
                byGift.get(bad.Id).Failure_Reason__c,
                'The reason is on the row, in the words the platform used.'
            );
            Assert.isNull(
                byGift.get(bad.Id).Gift_Key__c,
                'And the key is released, so the next send tries this gift again (R-AK7).'
            );
            Assert.areEqual(
                AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE,
                [SELECT Acknowledgment_Status__c FROM Gift__c WHERE Id = :bad.Id]
                .Acknowledgment_Status__c,
                'The gift that was not thanked for is still waiting, which is the whole point of ' +
                'retrying it.'
            );
        }
    }

    @IsTest
    static void aPersonPuttingAGiftBackInTheQueueGetsASecondThankYou() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();
            Contact donor = AcknowledgmentTestData.insertDonor(
                'Ada',
                'Lovelace',
                'ada@example.org'
            );
            Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 250);
            insert gift;

            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            AcknowledgmentService.senderOverride = sender;
            AcknowledgmentService.sendEmails(queuedGiftsInMemory(new List<Id>{ gift.Id }), null);

            Test.startTest();
            update new Gift__c(
                Id = gift.Id,
                Acknowledgment_Status__c = AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE
            );
            AcknowledgmentService.sendEmails(queuedGiftsInMemory(new List<Id>{ gift.Id }), null);
            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Acknowledgment__c WHERE Gift__c = :gift.Id],
                'Putting the gift back in the queue is the deliberate act that releases the key, and ' +
                'afterwards the gift shows two thank yous rather than one (R-AK7).'
            );
            Assert.areEqual(
                2,
                sender.received.size(),
                'Both of them were actually sent, which is what the donor experienced.'
            );
        }
    }

    @IsTest
    static void anOrganizationGiftWithNobodyToEmailIsCountedAndLeftAlone() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();
            Account organization = GivingTestDataFactory.insertOrganization('Riverside Trust');
            Gift__c gift = GivingTestDataFactory.buildAccountGift(organization.Id, 750);
            insert gift;

            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            AcknowledgmentService.senderOverride = sender;

            Test.startTest();
            AcknowledgmentService.SendCounts counts = AcknowledgmentService.sendEmails(
                queuedGiftsInMemory(new List<Id>{ gift.Id }),
                null
            );
            Test.stopTest();

            Assert.areEqual(0, counts.sent, 'There was nobody to email, so nothing was sent.');
            Assert.areEqual(
                1,
                counts.errors,
                'It is counted, so the run says something needs doing.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Acknowledgment__c WHERE Gift__c = :gift.Id],
                'And no row is written: nothing was attempted, so there is nothing to record on the ' +
                'donor (R-AK9).'
            );
            Assert.areEqual(
                AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE,
                [SELECT Acknowledgment_Status__c FROM Gift__c WHERE Id = :gift.Id]
                .Acknowledgment_Status__c,
                'The gift stays in the queue, where a letter rule or a corrected contact picks it up.'
            );
        }
    }

    @IsTest
    static void aDonorWhoOptedOutOfEmailIsNotEmailedAndStaysQueued() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentTestData.enable();
            emailRule();
            Contact ada = AcknowledgmentTestData.insertDonor('Ada', 'Lovelace', 'ada@example.org');
            Contact grace = AcknowledgmentTestData.insertDonor('Grace', 'Hopper', 'gh@example.org');
            Contact mary = AcknowledgmentTestData.insertDonor(
                'Mary',
                'Somerville',
                'm@example.org'
            );
            update new List<Contact>{
                new Contact(Id = grace.Id, HasOptedOutOfEmail = true),
                new Contact(Id = mary.Id, HasOptedOutOfEmail = true)
            };
            // An organization's thank you goes to its primary contact, so hers is the opt-out.
            Account trust = GivingTestDataFactory.insertOrganization('Riverside Trust');
            update new Account(Id = trust.Id, Primary_Contact__c = mary.Id);
            Gift__c toAda = GivingTestDataFactory.buildGift(ada.Id, 250);
            Gift__c toGrace = GivingTestDataFactory.buildGift(grace.Id, 250);
            Gift__c toTrust = GivingTestDataFactory.buildAccountGift(trust.Id, 750);
            insert new List<Gift__c>{ toAda, toGrace, toTrust };

            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            AcknowledgmentService.senderOverride = sender;

            Test.startTest();
            AcknowledgmentService.SendCounts counts = AcknowledgmentService.sendEmails(
                queuedGiftsInMemory(new List<Id>{ toAda.Id, toGrace.Id, toTrust.Id }),
                null
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                sender.received.size(),
                'Only Ada, who did not opt out, is emailed.'
            );
            Assert.areEqual(1, counts.sent, 'One thank you went.');
            Assert.areEqual(0, counts.errors, 'An opt-out is not an error (R-AK13).');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Acknowledgment__c WHERE Gift__c IN (:toGrace.Id, :toTrust.Id)],
                'Nothing was attempted for the opted-out donors, so no row is written.'
            );
            Assert.areEqual(
                2,
                [
                    SELECT COUNT()
                    FROM Gift__c
                    WHERE
                        Id IN (:toGrace.Id, :toTrust.Id)
                        AND Acknowledgment_Status__c = :AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE
                ],
                'Both stay in the queue for the letter run.'
            );
        }
    }

    @IsTest
    static void nothingIsQueuedWhileTheFeatureIsOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            emailRule();
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');

            Gift__c gift = GivingTestDataFactory.buildGift(donor.Id, 250);
            gift.Acknowledgment_Status__c = AcknowledgmentRuleService.STATUS_NOT_REQUIRED;
            insert gift;

            Assert.areEqual(
                AcknowledgmentRuleService.STATUS_NOT_REQUIRED,
                [SELECT Acknowledgment_Status__c FROM Gift__c WHERE Id = :gift.Id]
                .Acknowledgment_Status__c,
                'With acknowledgments off, the rules do not run at all and the status the gift was ' +
                'saved with stands (R-AK5).'
            );
        }
    }
}
