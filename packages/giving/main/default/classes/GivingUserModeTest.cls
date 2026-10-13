/**
 * The Giving package's user mode claim, tested as the people who live with it.
 *
 * Every query and every write in the Giving controllers runs in user mode on purpose, so that a
 * missing object or field permission shows up as a refused save with a sentence beside it rather
 * than as data quietly going nowhere. Nothing proved that until this class: the permission sets
 * it needs (`Giving_Admin`, `Giving_Staff`, `Giving_Read_Only`) did not exist when the
 * controllers were written, which is the gap recorded in
 * `packages/giving/integration/g-03-g-06.permissions.md`.
 *
 * The three people are the ones the admin guide is written for: Maria configures BarnCRM,
 * David enters the gifts, and Tom sits on the board and may look but not touch. Each of them is
 * given the Core set and the Giving set that the shipped permission set group pairs, because
 * that pairing is what a real org assigns; a Giving set alone carries no access to the people
 * the gifts are from.
 *
 * Read the refusals carefully: what is asserted is that the save did not happen, that nothing
 * was written, and that what came back is a sentence rather than a platform stack trace. The
 * exact wording is deliberately not asserted, because whether the platform refuses at the object
 * or at the field changes which of two messages the controller returns, and both are messages a
 * fundraiser can act on.
 */
@IsTest
private class GivingUserModeTest {
    private static final String ROLE_INFLUENCER = 'Influencer';
    private static final String TRIBUTE_IN_HONOR_OF = 'In honor of';

    /**
     * Maria, who configures BarnCRM.
     */
    private static User administrator() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
    }

    /**
     * David, who enters the gifts.
     */
    private static User fundraiser() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
        );
    }

    /**
     * Tom, on the board, who may look but not touch.
     */
    private static User boardMember() {
        return TestDataFactory.createUser(
            'Tom',
            new List<String>{ 'BarnCRM_Read_Only', 'Giving_Read_Only' }
        );
    }

    private static Fund__c defaultFund() {
        Fund__c fund = new Fund__c(Name = 'General', Active__c = true, Is_Default__c = true);
        insert fund;
        return fund;
    }

    /**
     * A donor who is the only person in her household, so that the gift she gives implies no
     * automatic household soft credits. This class is about the controllers, not about
     * recognition, and a second household member would drag recognition into every assertion.
     */
    private static Contact donor() {
        Contact person = new Contact(FirstName = 'Ana', LastName = 'Garcia');
        insert person;
        return person;
    }

    /**
     * Makes records belong to the person a test runs as. Gifts and commitments ship private, and
     * who can reach a person somebody else entered is the org's sharing model, which differs from
     * org to org. Handing the person the records keeps these tests about the permission sets, not
     * about sharing. A contact's household account goes with the contact, for an org where
     * contacts are shared through their account.
     */
    private static void handTo(User person, List<Id> recordIds) {
        List<Account> households = new List<Account>();
        for (Contact record : [
            SELECT AccountId
            FROM Contact
            WHERE Id IN :recordIds AND AccountId != NULL
        ]) {
            households.add(new Account(Id = record.AccountId, OwnerId = person.Id));
        }
        update households;
        List<SObject> handed = new List<SObject>();
        for (Id recordId : recordIds) {
            SObject owned = recordId.getSObjectType().newSObject(recordId);
            owned.put('OwnerId', person.Id);
            handed.add(owned);
        }
        update handed;
    }

    private static QuickGiftEntryController.GiftInput giftOf(Id donorContactId, Id fundId) {
        QuickGiftEntryController.GiftInput input = new QuickGiftEntryController.GiftInput();
        input.donorContactId = donorContactId;
        input.fundId = fundId;
        input.amount = 50;
        input.giftDate = Date.today();
        input.giftType = 'Check';
        return input;
    }

    /**
     * What a person entering gifts should see when they are not allowed to: a sentence, not the
     * name of an Apex exception.
     */
    private static void assertReadableRefusal(String message) {
        Assert.isTrue(String.isNotBlank(message), 'A refusal says something.');
        Assert.isFalse(
            message.containsIgnoreCase('exception'),
            'A fundraiser is told what happened, not which class threw: ' + message
        );
    }

    // ------------------------------------------------------------------- G-03 quick gift entry

    @IsTest
    static void anAdministratorSavesAGiftThroughQuickEntry() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User maria = administrator();
            Fund__c fund = defaultFund();
            Contact ana = donor();
            QuickGiftEntryController.SaveResult result;

            Test.startTest();
            System.runAs(maria) {
                result = QuickGiftEntryController.saveGift(giftOf(ana.Id, fund.Id));
            }
            Test.stopTest();

            Assert.isTrue(
                result.success,
                'Giving Admin carries what a gift needs: ' + result.formError
            );
            Assert.isNotNull(result.giftId, 'The saved gift is identified.');
            Assert.isNotNull(result.giftName, 'And named, so Maria can find it again.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Gift__c WHERE Id = :result.giftId],
                'The gift is really there, saved in user mode by Maria.'
            );
        }
    }

    @IsTest
    static void aFundraiserSavesAGiftThroughQuickEntry() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User david = fundraiser();
            Fund__c fund = defaultFund();
            Contact ana = donor();
            handTo(david, new List<Id>{ ana.Id });
            QuickGiftEntryController.SaveResult result;

            Test.startTest();
            System.runAs(david) {
                result = QuickGiftEntryController.saveGift(giftOf(ana.Id, fund.Id));
            }
            Test.stopTest();

            Assert.isTrue(
                result.success,
                'Giving Staff carries what a gift needs: ' + result.formError
            );
            Gift__c saved = [
                SELECT Donor_Contact__c, Amount__c, Status__c
                FROM Gift__c
                WHERE Id = :result.giftId
            ];
            Assert.areEqual(ana.Id, saved.Donor_Contact__c, 'The donor is the person David chose.');
            Assert.areEqual(50, saved.Amount__c, 'The amount is what David typed.');
            Assert.areEqual('Received', saved.Status__c, 'A gift entered at an event has arrived.');

            List<Gift_Allocation__c> allocations = [
                SELECT Fund__c, Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :result.giftId
            ];
            Assert.areEqual(1, allocations.size(), 'One gift, one allocation.');
            Assert.areEqual(fund.Id, allocations[0].Fund__c, 'Designated to the fund David chose.');
            Assert.areEqual(
                50,
                allocations[0].Amount__c,
                'The allocation the trigger created was moved, not added to.'
            );
        }
    }

    @IsTest
    static void aBoardMemberIsRefusedAGiftAndToldWhy() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User tom = boardMember();
            Fund__c fund = defaultFund();
            Contact ana = donor();
            QuickGiftEntryController.SaveResult result;

            Test.startTest();
            System.runAs(tom) {
                result = QuickGiftEntryController.saveGift(giftOf(ana.Id, fund.Id));
            }
            Test.stopTest();

            Assert.isFalse(result.success, 'Read Only carries no way to create a gift.');
            Assert.isNull(result.giftId, 'Nothing was identified, because nothing was saved.');
            Assert.isTrue(
                result.fieldErrors.isEmpty(),
                'The gift itself was fine: what stopped it was access, not the form.'
            );
            assertReadableRefusal(result.formError);
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'And no gift was written.');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Gift_Allocation__c],
                'Which is the point of user mode: a refused save leaves nothing behind.'
            );
        }
    }

    // -------------------------------------------------------------------------- G-04 reversals

    @IsTest
    static void aFundraiserRefundsAGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User david = fundraiser();
            defaultFund();
            Contact ana = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 100);
            insert gift;
            handTo(david, new List<Id>{ ana.Id, gift.Id });
            Id reversalId;

            Test.startTest();
            System.runAs(david) {
                reversalId = GiftController.refund(gift.Id, 40, 'Cheque returned unpaid');
            }
            Test.stopTest();

            Assert.isNotNull(reversalId, 'Giving Staff can record money going back.');
            Gift__c reversal = [
                SELECT Amount__c, Original_Gift__c, Refund_Reason__c
                FROM Gift__c
                WHERE Id = :reversalId
            ];
            Assert.areEqual(-40, reversal.Amount__c, 'A refund is a negative gift.');
            Assert.areEqual(gift.Id, reversal.Original_Gift__c, 'Linked to the gift it reverses.');
            Assert.areEqual(
                'Cheque returned unpaid',
                reversal.Refund_Reason__c,
                'Carrying the reason David gave.'
            );
        }
    }

    @IsTest
    static void aBoardMemberCannotRefundAGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User tom = boardMember();
            defaultFund();
            Contact ana = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 100);
            insert gift;
            String refusal = null;

            Test.startTest();
            System.runAs(tom) {
                try {
                    GiftController.refund(gift.Id, 40, 'Cheque returned unpaid');
                    Assert.fail('A board member cannot record a refund.');
                } catch (AuraHandledException refused) {
                    refusal = refused.getMessage();
                }
            }
            Test.stopTest();

            assertReadableRefusal(refusal);
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Gift__c],
                'The original gift is the only gift: no reversal was written.'
            );
        }
    }

    // ------------------------------------------------------------------------ G-06 soft credits

    @IsTest
    static void aBoardMemberCanReadTheSoftCreditPanelButNotAddToIt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User tom = boardMember();
            defaultFund();
            Contact ana = donor();
            Contact luis = new Contact(FirstName = 'Luis', LastName = 'Garcia');
            insert luis;
            Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 100);
            insert gift;
            insert new Soft_Credit__c(
                Gift__c = gift.Id,
                Contact__c = luis.Id,
                Role__c = ROLE_INFLUENCER,
                Amount__c = 100,
                Is_Automatic__c = false
            );
            // Tom can reach the gift, so what stops him adding a credit is his permission set.
            handTo(tom, new List<Id>{ ana.Id, luis.Id, gift.Id });
            SoftCreditController.SoftCreditPanel panel;
            String refusal = null;

            Test.startTest();
            System.runAs(tom) {
                panel = SoftCreditController.getCredits(gift.Id);
                try {
                    SoftCreditController.addCredit(gift.Id, luis.Id, ROLE_INFLUENCER, null, 100);
                    Assert.fail('A board member cannot add a soft credit.');
                } catch (AuraHandledException refused) {
                    refusal = refused.getMessage();
                }
            }
            Test.stopTest();

            Assert.areEqual(
                1,
                panel.credits.size(),
                'Tom can see the credit that is already there.'
            );
            Assert.isFalse(panel.canAdd, 'And the panel tells him he cannot add one.');
            assertReadableRefusal(refusal);
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Soft_Credit__c],
                'The credit he tried to add was not written.'
            );
        }
    }

    /*
     * There is deliberately no test here of David adding a soft credit. `addCredit` sets
     * `Is_Automatic__c` on the record it inserts in user mode, and neither `Giving_Staff` nor
     * `Giving_Admin` makes that field editable, so the save would be refused for a reason that
     * is a permission set omission rather than anything the controller does wrong. The omission
     * is recorded for the integrator in `packages/giving/integration/g-03-g-06.permissions.md`;
     * once the entry is added, the positive case belongs here beside its refusal.
     */

    // ---------------------------------------------------------------------------- G-09 tributes

    @IsTest
    static void aFundraiserMarksATributeNotified() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User david = fundraiser();
            defaultFund();
            Contact ana = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 100);
            insert gift;
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TRIBUTE_IN_HONOR_OF,
                'Luis Garcia'
            );
            insert tribute;
            handTo(david, new List<Id>{ ana.Id, gift.Id });
            TributeController.TributeView view;
            // Today as David's own clock has it. The date is stamped in the running user's time zone,
            // and the administrator running the suite can be on the other side of midnight from him.
            Date davidsToday;

            Test.startTest();
            System.runAs(david) {
                davidsToday = Date.today();
                view = TributeController.markNotificationSent(tribute.Id);
            }
            Test.stopTest();

            Assert.isNotNull(view, 'The panel comes back with the tribute as it now stands.');
            Tribute__c saved = [
                SELECT Notification_Sent__c, Notification_Sent_Date__c
                FROM Tribute__c
                WHERE Id = :tribute.Id
            ];
            Assert.isTrue(saved.Notification_Sent__c, 'David recorded that the letter went out.');
            Assert.areEqual(davidsToday, saved.Notification_Sent_Date__c, 'Dated today.');
        }
    }

    @IsTest
    static void aBoardMemberCannotMarkATributeNotified() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User tom = boardMember();
            defaultFund();
            Contact ana = donor();
            Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 100);
            insert gift;
            Tribute__c tribute = RecognitionTestData.tribute(
                gift.Id,
                TRIBUTE_IN_HONOR_OF,
                'Luis Garcia'
            );
            insert tribute;
            String refusal = null;

            Test.startTest();
            System.runAs(tom) {
                try {
                    TributeController.markNotificationSent(tribute.Id);
                    Assert.fail('A board member cannot record a notification.');
                } catch (AuraHandledException refused) {
                    refusal = refused.getMessage();
                }
            }
            Test.stopTest();

            assertReadableRefusal(refusal);
            Tribute__c unchanged = [
                SELECT Notification_Sent__c
                FROM Tribute__c
                WHERE Id = :tribute.Id
            ];
            Assert.isFalse(
                unchanged.Notification_Sent__c,
                'And the tribute still says the letter has not gone out.'
            );
        }
    }

    // ------------------------------------------------------------------------- G-05 commitments

    @IsTest
    static void aFundraiserPausesACommitment() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User david = fundraiser();
            defaultFund();
            Contact ana = donor();
            Commitment__c pledge = pledgeFor(ana.Id);
            handTo(david, new List<Id>{ ana.Id, pledge.Id });

            Test.startTest();
            System.runAs(david) {
                CommitmentController.changeStatus(pledge.Id, 'pause');
            }
            Test.stopTest();

            Assert.areEqual(
                'Paused',
                [SELECT Status__c FROM Commitment__c WHERE Id = :pledge.Id].Status__c,
                'Giving Staff can pause a pledge that has stopped being paid.'
            );
        }
    }

    @IsTest
    static void aBoardMemberCannotPauseACommitment() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User tom = boardMember();
            defaultFund();
            Contact ana = donor();
            Commitment__c pledge = pledgeFor(ana.Id);
            String refusal = null;

            Test.startTest();
            System.runAs(tom) {
                try {
                    CommitmentController.changeStatus(pledge.Id, 'pause');
                    Assert.fail('A board member cannot pause a pledge.');
                } catch (AuraHandledException refused) {
                    refusal = refused.getMessage();
                }
            }
            Test.stopTest();

            assertReadableRefusal(refusal);
            Assert.areEqual(
                'Active',
                [SELECT Status__c FROM Commitment__c WHERE Id = :pledge.Id].Status__c,
                'And the pledge is still running.'
            );
        }
    }

    private static Commitment__c pledgeFor(Id donorContactId) {
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = donorContactId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today().addMonths(1),
            Expected_Total__c = 300,
            Installments_Planned__c = 3
        );
        insert pledge;
        return pledge;
    }
}
