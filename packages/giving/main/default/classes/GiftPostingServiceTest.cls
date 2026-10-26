/**
 * Marking gifts posted and unposting them (G-20, R-G13, ADR-0053).
 *
 * Jen, the bookkeeper, holds Giving Admin, which carries Post Gifts. She marks last month posted
 * after her export, marks it again by mistake, and unposts one gift with a reason. David, on
 * Giving Staff, can do neither.
 */
@IsTest(testFor='ApexClass:GiftPostingService')
private class GiftPostingServiceTest {
    private static User jen() {
        return TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
    }

    private static User david() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
        );
    }

    /** The default fund is set by an administrator, not by the people in these tests. */
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
        }
    }

    /**
     * Three gifts owned by the running user: 250 and 40 Received, 75 Pending. Keyed by whole
     * amount, because a Decimal key read back as 250.00 is not the key 250.
     */
    private static Map<Integer, Gift__c> threeGifts() {
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        Gift__c received = GivingTestDataFactory.buildGift(ana.Id, 250);
        Gift__c pending = GivingTestDataFactory.buildGift(ana.Id, 75);
        pending.Status__c = 'Pending';
        Gift__c other = GivingTestDataFactory.buildGift(ana.Id, 40);
        insert new List<Gift__c>{ received, pending, other };
        Map<Integer, Gift__c> byAmount = new Map<Integer, Gift__c>();
        for (Gift__c gift : [
            SELECT Id, Amount__c, Accounting_Posted_At__c, Accounting_Posted_By__c
            FROM Gift__c
            WITH SYSTEM_MODE
        ]) {
            byAmount.put(gift.Amount__c.intValue(), gift);
        }
        return byAmount;
    }

    private static Gift__c reread(Id giftId) {
        return [
            SELECT Id, Amount__c, Accounting_Posted_At__c, Accounting_Posted_By__c
            FROM Gift__c
            WHERE Id = :giftId
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void marksGiftsInTheBooksPostedByTheBookkeeper() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User jen = jen();
            System.runAs(jen) {
                Map<Integer, Gift__c> gifts = threeGifts();

                Test.startTest();
                Integer marked = GiftPostingService.markPosted(
                    new Map<Id, Gift__c>(gifts.values()).keySet()
                );
                Test.stopTest();

                Assert.areEqual(
                    2,
                    marked,
                    'The two Received gifts are marked, the Pending one is not'
                );
                Gift__c posted = reread(gifts.get(250).Id);
                Assert.isNotNull(posted.Accounting_Posted_At__c, 'Marked with the time');
                Assert.areEqual(jen.Id, posted.Accounting_Posted_By__c, 'Marked with who');
                Assert.isNull(
                    reread(gifts.get(75).Id).Accounting_Posted_At__c,
                    'A Pending gift is in no export file'
                );
            }

        }
    }

    @IsTest
    static void markingTwiceChangesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(jen()) {
                Map<Integer, Gift__c> gifts = threeGifts();
                Set<Id> ids = new Set<Id>{ gifts.get(250).Id };
                GiftPostingService.markPosted(ids);
                Datetime first = reread(gifts.get(250).Id).Accounting_Posted_At__c;

                Integer again = GiftPostingService.markPosted(ids);

                Assert.areEqual(0, again, 'An already posted gift is not marked again');
                Assert.areEqual(
                    first,
                    reread(gifts.get(250).Id).Accounting_Posted_At__c,
                    'The first posting time is kept'
                );
            }

        }
    }

    @IsTest
    static void aPostedGiftIsLocked() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(jen()) {
                Map<Integer, Gift__c> gifts = threeGifts();
                GiftPostingService.markPosted(new Set<Id>{ gifts.get(250).Id });

                Gift__c changed = new Gift__c(Id = gifts.get(250).Id, Amount__c = 260);
                try {
                    update changed;
                    Assert.fail('A posted gift keeps its amount');
                } catch (DmlException refused) {
                    Assert.areEqual(
                        Label.Giving_Posting_PostedGiftLocked,
                        refused.getDmlMessage(0),
                        'Refused with the posted gift message'
                    );
                }
            }

        }
    }

    @IsTest
    static void staffCannotMarkOrUnpost() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(david()) {
                Map<Integer, Gift__c> gifts = threeGifts();
                Set<Id> ids = new Set<Id>{ gifts.get(250).Id };
                try {
                    GiftPostingService.markPosted(ids);
                    Assert.fail('Marking posted needs Post Gifts');
                } catch (GiftPostingService.GiftPostingException refused) {
                    Assert.areEqual(Label.Giving_Posting_NoPermission, refused.getMessage());
                }
                try {
                    GiftPostingService.unpost(gifts.get(250).Id, 'Typo');
                    Assert.fail('Unposting needs Post Gifts');
                } catch (GiftPostingService.GiftPostingException refused) {
                    Assert.areEqual(Label.Giving_Posting_NoPermission, refused.getMessage());
                }
                Assert.isNull(reread(gifts.get(250).Id).Accounting_Posted_At__c, 'Nothing marked');
            }

        }
    }

    @IsTest
    static void staffCannotWriteThePostingFieldsDirectly() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<Integer, Gift__c> gifts;
            System.runAs(david()) {
                gifts = threeGifts();
            }
            // Saved as the administrator running the test, who may edit the field: field access
            // does not refuse it, so the refusal checked here is the lock's.
            Gift__c typed = new Gift__c(
                Id = gifts.get(250).Id,
                Accounting_Posted_At__c = Datetime.now()
            );
            try {
                update typed;
                Assert.fail('The posting fields are written only by marking posted');
            } catch (DmlException refused) {
                Assert.areEqual(
                    Label.Giving_Posting_FieldsWrittenByPosting,
                    refused.getDmlMessage(0),
                    'The lock refuses it'
                );
            }
            Assert.isNull(reread(gifts.get(250).Id).Accounting_Posted_At__c, 'Nothing written');
        }
    }

    @IsTest
    static void refusesMoreThanOneClickCanMark() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GiftPostingService.postPermission = true;
            String prefix = Gift__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getKeyPrefix();
            Set<Id> tooMany = new Set<Id>();
            for (Integer i = 0; i <= GiftPostingService.MAX_GIFTS_PER_MARK; i++) {
                tooMany.add(Id.valueOf(prefix + String.valueOf(i).leftPad(12, '0')));
            }
            try {
                GiftPostingService.markPosted(tooMany);
                Assert.fail('More than the cap is refused before anything is read');
            } catch (GiftPostingService.GiftPostingException refused) {
                Assert.isTrue(
                    refused.getMessage()
                        .contains(String.valueOf(GiftPostingService.MAX_GIFTS_PER_MARK)),
                    'The message names the cap'
                );
            }
        }
    }

    @IsTest
    static void unpostingClearsTheMarkAndLogsTheReason() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User jen = jen();
            Id giftId;
            String postedAt;
            System.runAs(jen) {
                Map<Integer, Gift__c> gifts = threeGifts();
                giftId = gifts.get(250).Id;
                GiftPostingService.markPosted(new Set<Id>{ giftId });
                postedAt = reread(giftId).Accounting_Posted_At__c.format();

                Test.startTest();
                GiftPostingService.unpost(giftId, '  Wrong fund, fixing before the next export ');
                Test.stopTest();

                Gift__c unposted = reread(giftId);
                Assert.isNull(unposted.Accounting_Posted_At__c, 'The time is cleared');
                Assert.isNull(unposted.Accounting_Posted_By__c, 'The person is cleared');
                update new Gift__c(Id = giftId, Amount__c = 260);
                Assert.areEqual(260, reread(giftId).Amount__c, 'An unposted open gift can change');
            }
            List<Error_Log__c> logs = [
                SELECT Message__c, Severity__c, User__c
                FROM Error_Log__c
                WHERE Context__c = 'Gift unposted'
            ];
            Assert.areEqual(1, logs.size(), 'One log entry per unposted gift');
            Assert.areEqual(ErrorLogger.SEVERITY_WARNING, logs[0].Severity__c);
            Assert.isTrue(
                logs[0].Message__c.endsWith(': Wrong fund, fixing before the next export'),
                'The reason is kept: ' + logs[0].Message__c
            );
            Assert.isTrue(
                logs[0]
                    .Message__c.contains(
                        'posted to accounting by Jen on ' + postedAt + ', unposted'
                    ),
                'Who posted it and when are kept: ' + logs[0].Message__c
            );
            Assert.areEqual(jen.Id, logs[0].User__c, 'The log says who unposted');
        }
    }

    @IsTest
    static void unpostingNeedsAReasonAndAPostedGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(jen()) {
                Map<Integer, Gift__c> gifts = threeGifts();
                Id giftId = gifts.get(250).Id;
                try {
                    GiftPostingService.unpost(giftId, 'Never posted');
                    Assert.fail('A gift that is not posted cannot be unposted');
                } catch (GiftPostingService.GiftPostingException refused) {
                    Assert.areEqual(Label.Giving_Posting_NotPosted, refused.getMessage());
                }
                GiftPostingService.markPosted(new Set<Id>{ giftId });
                try {
                    GiftPostingService.unpost(giftId, '   ');
                    Assert.fail('A reason is required');
                } catch (GiftPostingService.GiftPostingException refused) {
                    Assert.areEqual(Label.Giving_Posting_ReasonRequired, refused.getMessage());
                }
                Assert.isNotNull(reread(giftId).Accounting_Posted_At__c, 'Still posted');
            }

        }
    }

    @IsTest
    static void unpostingAClosedPeriodGiftLeavesItLocked() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            // Closing the books is the administrator's step, done before Jen's work.
            GivingTestDataFactory.closeBooksThrough(Date.today().addDays(-1));
            System.runAs(jen()) {
                Map<Integer, Gift__c> gifts = threeGifts();
                Id giftId = gifts.get(250).Id;
                GiftPostingService.markPosted(new Set<Id>{ giftId });
                // Date the gift into the closed period through the override, as an auditor would.
                GiftPostingLock.overrideHeld = true;
                update new Gift__c(Id = giftId, Gift_Date__c = Date.today().addDays(-5));
                GiftPostingLock.overrideHeld = false;

                GiftPostingService.unpost(giftId, 'Posted to the wrong account');

                Assert.isNull(reread(giftId).Accounting_Posted_At__c, 'Unposted');
                try {
                    update new Gift__c(Id = giftId, Amount__c = 1);
                    Assert.fail('Still in a closed period');
                } catch (DmlException refused) {
                    Assert.isTrue(
                        refused.getDmlMessage(0).startsWith('This gift is dated in a closed'),
                        refused.getDmlMessage(0)
                    );
                }
            }

        }
    }

    @IsTest
    static void theSwitchableAutomationsAreBypassedOnlyForThePostingSave() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(jen()) {
                Map<Integer, Gift__c> gifts = threeGifts();
                AutomationControl.bypass('Gift_Acknowledgment');

                GiftPostingService.markPosted(new Set<Id>{ gifts.get(250).Id });

                Assert.isFalse(
                    AutomationControl.isBypassed('Gift_Core_Rules'),
                    'The bypass ends with the save'
                );
                Assert.isTrue(
                    AutomationControl.isBypassed('Gift_Acknowledgment'),
                    'A bypass the caller set is left as it was'
                );
            }

        }
    }

    @IsTest
    static void inKindGiftsAreNotInTheBooks() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isFalse(
                GiftPostingLock.isInBooks(new Gift__c(Status__c = 'Received', Type__c = 'In-kind')),
                'An in-kind gift is in no export file, so it is never marked posted'
            );
        }
    }
}
