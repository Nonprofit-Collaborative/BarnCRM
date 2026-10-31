/**
 * The Ask Pipeline board (G-26): its totals and cards (R-SO6), moving an ask, and closing one with
 * what a win produced (R-SO5), all or nothing.
 */
@IsTest(testFor='ApexClass:AskPipelineController, ApexClass:AskSelector')
private class AskPipelineControllerTest {
    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith('Giving_Staff');
    }

    private static User staff() {
        return TestUsers.adminWith('Giving_Staff');
    }

    private static Contact donor(String lastName) {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        GivingTestDataFactory.ensureDefaultFund();
        return GivingTestDataFactory.insertHouseholdContact(
            'The ' + lastName + ' Family',
            'Jordan',
            lastName
        );
    }

    private static Ask__c ask(Id contactId, String stage, Decimal amount) {
        return new Ask__c(Donor_Contact__c = contactId, Stage__c = stage, Amount__c = amount);
    }

    private static AskPipelineController.CloseInput won(Id askId, String result) {
        AskPipelineController.CloseInput input = new AskPipelineController.CloseInput();
        input.askId = askId;
        input.outcome = AskRules.OUTCOME_WON;
        input.result = result;
        return input;
    }

    @IsTest
    static void theBoardTotalsEveryStageAndTheYear() {
        System.runAs(staff()) {
            Contact lee = donor('Lee');
            insert new List<Ask__c>{
                ask(lee.Id, 'Identified', 1000),
                ask(lee.Id, 'Identified', 500),
                ask(lee.Id, 'Asked', 2500),
                new Ask__c(Donor_Contact__c = lee.Id, Outcome__c = 'Won', Amount__c = 750),
                new Ask__c(Donor_Contact__c = lee.Id, Outcome__c = 'Declined', Amount__c = 300)
            };

            Test.startTest();
            AskPipelineController.Board board = AskPipelineController.getBoard(false);
            Test.stopTest();

            Assert.areEqual(AskRules.stages(), board.stages, 'The org stages, in order.');
            Assert.areEqual(3, board.openCount, 'Three open asks.');
            Assert.areEqual(4000, board.openAmount, 'Their ask amounts.');
            Assert.areEqual(3, board.cards.size(), 'One card each.');
            Assert.isFalse(board.truncated, 'Every card is drawn.');
            Map<String, AskPipelineController.Total> byStage = new Map<String, AskPipelineController.Total>();
            for (AskPipelineController.Total total : board.stageTotals) {
                byStage.put(total.stage, total);
            }
            Assert.areEqual(2, byStage.get('Identified').count, 'Two identified.');
            Assert.areEqual(1500, byStage.get('Identified').amount, 'Totalled.');
            Assert.areEqual(1, board.wonCount, 'One won this year.');
            Assert.areEqual(750, board.wonAmount, 'Its ask amount.');
            Assert.areEqual(1, board.declinedCount, 'One declined this year.');
            Assert.isTrue(board.canEdit, 'Staff may move asks.');
            Assert.isFalse(board.giftTypes.isEmpty(), 'Gift types for the Won dialog.');
            Assert.isFalse(board.frequencies.isEmpty(), 'Frequencies for a pledge.');
            Assert.areEqual('Jordan Lee', board.cards[0].donorName, 'The donor on the card.');
        }
    }

    @IsTest
    static void totalsStayExactWhenTheCardsAreCut() {
        System.runAs(staff()) {
            Contact lee = donor('Lee');
            insert new List<Ask__c>{ ask(lee.Id, 'Asked', 100), ask(lee.Id, 'Asked', 200) };
            AskPipelineController.maxCards = 1;

            Test.startTest();
            AskPipelineController.Board board = AskPipelineController.getBoard(true);
            Test.stopTest();

            Assert.areEqual(1, board.cards.size(), 'One card drawn.');
            Assert.isTrue(board.truncated, 'The board says it is cut.');
            Assert.areEqual(300, board.openAmount, 'The total still counts both.');
        }
    }

    @IsTest
    static void movesAnAskAndRefusesAStageNotInTheList() {
        System.runAs(staff()) {
            Contact lee = donor('Lee');
            Ask__c open = ask(lee.Id, 'Identified', 100);
            insert open;

            Test.startTest();
            AskPipelineController.moveStage(open.Id, 'Cultivating');
            String refusal;
            try {
                AskPipelineController.moveStage(open.Id, 'Negotiating');
            } catch (AuraHandledException e) {
                refusal = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                'Cultivating',
                [SELECT Stage__c FROM Ask__c WHERE Id = :open.Id].Stage__c,
                'Moved.'
            );
            Assert.isTrue(
                refusal != null && refusal.contains('Negotiating'),
                'A stage not in the list is refused by name.'
            );
        }
    }

    @IsTest
    static void aWinRecordsTheGiftWithTheAsksDonorFundAndAppeal() {
        System.runAs(staff()) {
            Contact lee = donor('Lee');
            Appeal__c spring = GivingTestDataFactory.buildAppeal('Spring Appeal');
            insert spring;
            Ask__c open = ask(lee.Id, 'Asked', 2500);
            open.Appeal__c = spring.Id;
            insert open;
            AskPipelineController.CloseInput input = won(
                open.Id,
                AskPipelineController.RESULT_GIFT
            );
            input.amount = 2000;
            input.giftDate = System.today();
            input.giftType = 'Check';
            input.nextAskDate = System.today().addYears(1);

            Test.startTest();
            AskPipelineController.CloseResult result = AskPipelineController.closeAsk(input);
            Test.stopTest();

            Assert.isTrue(result.success, 'Closed: ' + result.error);
            Ask__c closed = [
                SELECT Outcome__c, Gift__c, Closed_Date__c, Next_Ask_Date__c
                FROM Ask__c
                WHERE Id = :open.Id
            ];
            Assert.areEqual(AskRules.OUTCOME_WON, closed.Outcome__c, 'Won.');
            Assert.areEqual(result.giftId, closed.Gift__c, 'Linked to the new gift.');
            Assert.areEqual(System.today(), closed.Closed_Date__c, 'Closed today.');
            Assert.areEqual(System.today().addYears(1), closed.Next_Ask_Date__c, 'Next ask kept.');
            Gift__c gift = [
                SELECT Donor_Contact__c, Amount__c, Appeal__c, Type__c
                FROM Gift__c
                WHERE Id = :closed.Gift__c
            ];
            Assert.areEqual(lee.Id, gift.Donor_Contact__c, 'From the ask donor.');
            Assert.areEqual(2000, gift.Amount__c, 'For the amount given.');
            Assert.areEqual(spring.Id, gift.Appeal__c, 'Credited to the ask appeal.');
        }
    }

    @IsTest
    static void aWinRecordsAPledgeInEqualPayments() {
        System.runAs(staff()) {
            Contact lee = donor('Lee');
            Ask__c open = ask(lee.Id, 'Asked', 1000);
            insert open;
            AskPipelineController.CloseInput input = won(
                open.Id,
                AskPipelineController.RESULT_PLEDGE
            );
            input.amount = 1000;
            input.payments = 3;
            input.frequency = 'Monthly';
            input.giftDate = System.today().addDays(10);

            Test.startTest();
            AskPipelineController.CloseResult result = AskPipelineController.closeAsk(input);
            Test.stopTest();

            Assert.isTrue(result.success, 'Closed: ' + result.error);
            Commitment__c pledge = [
                SELECT
                    Type__c,
                    Expected_Total__c,
                    Amount__c,
                    Installments_Planned__c,
                    Donor_Contact__c
                FROM Commitment__c
                WHERE Id = :result.commitmentId
            ];
            Assert.areEqual('Pledge', pledge.Type__c, 'A pledge.');
            Assert.areEqual(1000, pledge.Expected_Total__c, 'For the total.');
            Assert.areEqual(333.33, pledge.Amount__c, 'In equal payments.');
            Assert.areEqual(3, pledge.Installments_Planned__c, 'Three of them.');
            Assert.areEqual(lee.Id, pledge.Donor_Contact__c, 'From the ask donor.');
            Assert.areEqual(
                pledge.Id,
                [SELECT Commitment__c FROM Ask__c WHERE Id = :open.Id].Commitment__c,
                'Linked.'
            );
        }
    }

    @IsTest
    static void aWinLinksTheDonorsOwnGiftOnly() {
        System.runAs(staff()) {
            Contact lee = donor('Lee');
            Contact park = donor('Park');
            Gift__c leeGift = GivingTestDataFactory.buildGift(lee.Id, 400);
            Gift__c parkGift = GivingTestDataFactory.buildGift(park.Id, 400);
            insert new List<Gift__c>{ leeGift, parkGift };
            Ask__c open = ask(lee.Id, 'Asked', 400);
            insert open;

            Test.startTest();
            AskPipelineController.CloseInput wrong = won(
                open.Id,
                AskPipelineController.RESULT_LINK
            );
            wrong.linkedId = parkGift.Id;
            AskPipelineController.CloseResult refused = AskPipelineController.closeAsk(wrong);
            AskPipelineController.CloseInput right = won(
                open.Id,
                AskPipelineController.RESULT_LINK
            );
            right.linkedId = leeGift.Id;
            AskPipelineController.CloseResult linked = AskPipelineController.closeAsk(right);
            Test.stopTest();

            Assert.isFalse(refused.success, 'Another donor gift is refused.');
            Assert.areEqual(Label.Giving_Ask_ErrorWrongDonor, refused.error, 'And says why.');
            Assert.isTrue(linked.success, 'The donor gift is linked: ' + linked.error);
            Assert.areEqual(
                leeGift.Id,
                [SELECT Gift__c FROM Ask__c WHERE Id = :open.Id].Gift__c,
                'Linked.'
            );
        }
    }

    @IsTest
    static void aGiftThatCannotBeSavedLeavesTheAskOpen() {
        System.runAs(staff()) {
            Contact lee = donor('Lee');
            Ask__c open = ask(lee.Id, 'Asked', 400);
            insert open;
            AskPipelineController.CloseInput input = won(
                open.Id,
                AskPipelineController.RESULT_GIFT
            );
            input.amount = 0;
            input.giftDate = System.today();
            input.giftType = 'Check';

            Test.startTest();
            AskPipelineController.CloseResult result = AskPipelineController.closeAsk(input);
            Test.stopTest();

            Assert.isFalse(result.success, 'Refused.');
            Assert.isNotNull(result.error, 'With a sentence.');
            Assert.areEqual(
                AskRules.OUTCOME_OPEN,
                [SELECT Outcome__c FROM Ask__c WHERE Id = :open.Id].Outcome__c,
                'Still open.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift.');
        }
    }

    @IsTest
    static void declinedAndWithdrawnCloseWithoutAResult() {
        System.runAs(staff()) {
            Contact lee = donor('Lee');
            Ask__c open = ask(lee.Id, 'Asked', 400);
            Ask__c planned = ask(lee.Id, 'Identified', 100);
            insert new List<Ask__c>{ open, planned };
            AskPipelineController.CloseInput declined = new AskPipelineController.CloseInput();
            declined.askId = open.Id;
            declined.outcome = AskRules.OUTCOME_DECLINED;
            AskPipelineController.CloseInput bad = new AskPipelineController.CloseInput();
            bad.askId = planned.Id;
            bad.outcome = AskRules.OUTCOME_OPEN;

            Test.startTest();
            AskPipelineController.CloseResult result = AskPipelineController.closeAsk(declined);
            AskPipelineController.CloseResult notClosed = AskPipelineController.closeAsk(bad);
            AskPipelineController.CloseResult missing = AskPipelineController.closeAsk(null);
            Test.stopTest();

            Assert.isTrue(result.success, 'Declined: ' + result.error);
            Assert.areEqual(
                AskRules.OUTCOME_DECLINED,
                [SELECT Outcome__c FROM Ask__c WHERE Id = :open.Id].Outcome__c,
                'Declined.'
            );
            Assert.areEqual(Label.Giving_Ask_ErrorOutcome, notClosed.error, 'Open is no close.');
            Assert.areEqual(Label.Giving_Ask_ErrorNotFound, missing.error, 'Nothing to close.');
        }
    }

    @IsTest
    static void aReaderSeesTheBoardButChangesNothing() {
        Ask__c open;
        System.runAs(staff()) {
            open = ask(donor('Lee').Id, 'Asked', 400);
            insert open;
        }
        // A read-only profile, so the profile grants no edit the permission set does not.
        User reader = TestUsers.peopleReaderWith(
            'AskReader',
            new List<String>{ 'Giving_Read_Only' }
        );
        System.runAs(reader) {
            Test.startTest();
            AskPipelineController.Board board = AskPipelineController.getBoard(false);
            AskPipelineController.CloseInput input = won(
                open.Id,
                AskPipelineController.RESULT_LATER
            );
            AskPipelineController.CloseResult result = AskPipelineController.closeAsk(input);
            String refusal;
            try {
                AskPipelineController.moveStage(open.Id, 'Identified');
            } catch (AuraHandledException e) {
                refusal = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(1, board.cards.size(), 'A reader sees the ask.');
            Assert.isFalse(board.canEdit, 'But may not change it.');
            Assert.areEqual(Label.Giving_Ask_ErrorNoPermission, result.error, 'Closing refused.');
            Assert.areEqual(Label.Giving_Ask_ErrorNoPermission, refusal, 'Moving refused.');
        }
    }
}
