/**
 * Tests for posting a gift batch (G-17), run as David, who enters the gifts and holds only the
 * staff permission sets, so they also prove those sets carry everything posting needs.
 *
 * The Tuesday mail: a check from Ana Garcia, a check from the Riverside Foundation, and a
 * deposit slip that says how much they came to.
 */
@IsTest
private class GiftBatchServiceTest {
    private static User david() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
        );
    }

    private static Fund__c fund(String name, Boolean isDefault) {
        Fund__c fund = new Fund__c(Name = name, Active__c = true, Is_Default__c = isDefault);
        insert fund;
        return fund;
    }

    private static Appeal__c appeal(String name) {
        Appeal__c appeal = new Appeal__c(Name = name, Active__c = true);
        insert appeal;
        return appeal;
    }

    private static Contact person() {
        Contact donor = new Contact(FirstName = 'Ana', LastName = 'Garcia');
        insert donor;
        return donor;
    }

    private static Account organization() {
        Account donor = new Account(Name = 'Riverside Foundation');
        insert donor;
        return donor;
    }

    private static Gift_Batch__c batch(Decimal controlTotal, Id fundId, Id appealId) {
        Gift_Batch__c batch = new Gift_Batch__c(
            Description__c = 'Tuesday mail',
            Control_Total__c = controlTotal,
            Default_Gift_Date__c = Date.newInstance(2026, 3, 14),
            Default_Payment_Method__c = 'Check',
            Default_Fund__c = fundId,
            Default_Appeal__c = appealId
        );
        insert batch;
        return batch;
    }

    private static Gift_Batch_Row__c line(Id batchId, Id contactId, Id accountId, Decimal amount) {
        return new Gift_Batch_Row__c(
            Gift_Batch__c = batchId,
            Donor_Contact__c = contactId,
            Donor_Account__c = accountId,
            Amount__c = amount
        );
    }

    @IsTest
    static void aBalancedBatchPostsOrdinaryGiftsFromItsLinesAndDefaults() {
        Fund__c general = fund('General', true);
        Fund__c building = fund('Building Fund', false);
        Appeal__c spring = appeal('Spring Appeal');
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Account riverside = organization();
            Gift_Batch__c tuesday = batch(350, null, spring.Id);
            Gift_Batch_Row__c first = line(tuesday.Id, ana.Id, null, 100);
            first.Payment_Reference__c = '1042';
            Gift_Batch_Row__c second = line(tuesday.Id, null, riverside.Id, 250);
            second.Fund__c = building.Id;
            second.Payment_Method__c = 'ACH';
            insert new List<Gift_Batch_Row__c>{ first, second };

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isTrue(outcome.success, 'A balanced batch posts: ' + outcome.formError);
            Assert.areEqual(2, outcome.giftCount, 'One gift per line.');

            Map<Id, Gift_Batch_Row__c> lines = new Map<Id, Gift_Batch_Row__c>(
                [SELECT Id, Gift__c FROM Gift_Batch_Row__c WHERE Gift_Batch__c = :tuesday.Id]
            );
            Gift__c anaGift = [
                SELECT
                    Donor_Contact__c,
                    Amount__c,
                    Gift_Date__c,
                    Type__c,
                    Status__c,
                    Appeal__c,
                    Payment_Reference__c
                FROM Gift__c
                WHERE Id = :lines.get(first.Id).Gift__c
            ];
            Assert.areEqual(ana.Id, anaGift.Donor_Contact__c, 'The line donor gave the gift.');
            Assert.areEqual(100, anaGift.Amount__c, 'The line amount is the gift amount.');
            Assert.areEqual(
                Date.newInstance(2026, 3, 14),
                anaGift.Gift_Date__c,
                'A line with no date takes the batch date.'
            );
            Assert.areEqual('Check', anaGift.Type__c, 'A line with no method takes the batch one.');
            Assert.areEqual('Received', anaGift.Status__c, 'A posted gift has been received.');
            Assert.areEqual(
                spring.Id,
                anaGift.Appeal__c,
                'A line with no appeal takes the batch one.'
            );
            Assert.areEqual('1042', anaGift.Payment_Reference__c, 'The check number is carried.');

            Gift__c riversideGift = [
                SELECT Type__c
                FROM Gift__c
                WHERE Id = :lines.get(second.Id).Gift__c
            ];
            Assert.areEqual('ACH', riversideGift.Type__c, 'A line keeps a method of its own.');

            Assert.areEqual(
                general.Id,
                [SELECT Fund__c FROM Gift_Allocation__c WHERE Gift__c = :anaGift.Id].Fund__c,
                'With no fund on the line or the batch, the gift lands in the default fund.'
            );
            Gift_Allocation__c buildingAllocation = [
                SELECT Fund__c, Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__c = :riversideGift.Id
            ];
            Assert.areEqual(building.Id, buildingAllocation.Fund__c, 'The line fund is used.');
            Assert.areEqual(250, buildingAllocation.Amount__c, 'The allocation totals the gift.');

            Assert.areEqual(
                'Posted',
                [SELECT Status__c FROM Gift_Batch__c WHERE Id = :tuesday.Id].Status__c,
                'The batch is closed by posting.'
            );
        }
    }

    @IsTest
    static void aLineFundIsKeptWhenGiftAutomationIsPaused() {
        // Paused automation creates no default allocation, so the line's designation has to be
        // written as a new allocation rather than repointed, or it is lost without a word.
        fund('General', true);
        Fund__c building = fund('Building Fund', false);
        TestDataFactory.pausedSettings(1);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Account riverside = organization();
            Gift_Batch__c tuesday = batch(250, null, null);
            Gift_Batch_Row__c only = line(tuesday.Id, null, riverside.Id, 250);
            only.Fund__c = building.Id;
            insert only;

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isTrue(AutomationControl.isPaused(), 'Gift automation was paused throughout.');
            Assert.isTrue(outcome.success, 'The batch posts: ' + outcome.formError);
            Gift_Allocation__c allocation = [
                SELECT Fund__c, Amount__c
                FROM Gift_Allocation__c
                WHERE Gift__r.Donor_Account__c = :riverside.Id
            ];
            Assert.areEqual(building.Id, allocation.Fund__c, 'The line fund is still used.');
            Assert.areEqual(250, allocation.Amount__c, 'The allocation is the whole gift.');
        }
    }

    @IsTest
    static void aLineLeftEmptyFollowsADefaultCorrectedBeforePosting() {
        fund('General', true);
        Appeal__c fall = appeal('Fall Appeal');
        Appeal__c spring = appeal('Spring Appeal');
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Gift_Batch__c tuesday = batch(100, null, fall.Id);
            insert line(tuesday.Id, ana.Id, null, 100);
            tuesday.Default_Appeal__c = spring.Id;
            update tuesday;

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isTrue(outcome.success, 'The batch posts: ' + outcome.formError);
            Assert.areEqual(
                spring.Id,
                [SELECT Appeal__c FROM Gift__c WHERE Donor_Contact__c = :ana.Id].Appeal__c,
                'Correcting the batch default corrects every line that did not choose its own.'
            );
        }
    }

    @IsTest
    static void aBatchOutOfBalanceIsRefusedWithTheDifferenceAndCreatesNothing() {
        fund('General', true);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Gift_Batch__c shortBatch = batch(112.50, null, null);
            insert line(shortBatch.Id, ana.Id, null, 100);
            Gift_Batch__c overBatch = batch(90, null, null);
            insert line(overBatch.Id, ana.Id, null, 100);

            Test.startTest();
            GiftBatchService.PostOutcome shortOutcome = GiftBatchService.post(shortBatch.Id);
            GiftBatchService.PostOutcome overOutcome = GiftBatchService.post(overBatch.Id);
            Test.stopTest();

            Assert.isFalse(shortOutcome.success, 'A short batch does not post.');
            Assert.areEqual(
                Label.Giving_GiftBatch_ErrorShortOfControlTotal.replace('{0}', '12.50'),
                shortOutcome.formError,
                'It says how far out, to the cent, and which way, as the grid does.'
            );
            Assert.isFalse(overOutcome.success, 'An over batch does not post.');
            Assert.areEqual(
                Label.Giving_GiftBatch_ErrorOverControlTotal.replace('{0}', '10.00'),
                overOutcome.formError,
                'A whole number of dollars still shows its cents.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'Nothing was created.');
        }
    }

    @IsTest
    static void aBatchWithNoLinesOrNoControlTotalIsRefused() {
        fund('General', true);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Gift_Batch__c empty = batch(100, null, null);
            Gift_Batch__c unchecked = batch(null, null, null);
            insert line(unchecked.Id, ana.Id, null, 100);

            Test.startTest();
            GiftBatchService.PostOutcome emptyOutcome = GiftBatchService.post(empty.Id);
            GiftBatchService.PostOutcome uncheckedOutcome = GiftBatchService.post(unchecked.Id);
            GiftBatchService.PostOutcome missingOutcome = GiftBatchService.post(null);
            Test.stopTest();

            Assert.areEqual(Label.Giving_GiftBatch_ErrorNoRows, emptyOutcome.formError, 'Empty.');
            Assert.areEqual(
                Label.Giving_GiftBatch_ErrorNoControlTotal,
                uncheckedOutcome.formError,
                'Nothing to check against.'
            );
            Assert.areEqual(
                Label.Giving_GiftBatch_ErrorBatchMissing,
                missingOutcome.formError,
                'No batch.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'Nothing was created.');
        }
    }

    @IsTest
    static void unfinishedLinesAreAllNamedAndNothingIsPosted() {
        fund('General', true);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Account riverside = organization();
            Gift_Batch__c tuesday = batch(100, null, null);
            tuesday.Default_Payment_Method__c = null;
            update tuesday;
            insert new List<Gift_Batch_Row__c>{
                line(tuesday.Id, null, null, 60),
                line(tuesday.Id, ana.Id, riverside.Id, 40),
                line(tuesday.Id, ana.Id, null, 0)
            };

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isFalse(outcome.success, 'Unfinished lines stop the post.');
            Assert.areEqual(Label.Giving_GiftBatch_ErrorRowsIncomplete, outcome.formError, 'Why.');
            Set<String> found = new Set<String>();
            for (GiftBatchService.LineProblem problem : outcome.lineProblems) {
                found.add(problem.lineNumber + ':' + problem.message);
            }
            Assert.isTrue(found.contains('1:' + Label.Giving_GiftBatch_ErrorRowDonorMissing), '1');
            Assert.isTrue(found.contains('2:' + Label.Giving_GiftBatch_ErrorRowDonorBoth), '2');
            Assert.isTrue(found.contains('3:' + Label.Giving_GiftBatch_ErrorRowAmount), '3');
            Assert.isTrue(
                found.contains('1:' + Label.Giving_GiftBatch_ErrorRowPaymentMethod),
                'With no method anywhere, every line is missing one.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'Nothing was created.');
        }
    }

    @IsTest
    static void aLineThePlatformRefusesRollsTheWholeBatchBack() {
        // No fund exists at all, so the gift triggers refuse every gift: the org has nowhere to
        // allocate them. That is a real first-week mistake, and it must leave nothing behind.
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Gift_Batch__c tuesday = batch(150, null, null);
            insert new List<Gift_Batch_Row__c>{
                line(tuesday.Id, ana.Id, null, 100),
                line(tuesday.Id, ana.Id, null, 50)
            };

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isFalse(outcome.success, 'The post fails.');
            Assert.areEqual(Label.Giving_GiftBatch_ErrorPostFailed, outcome.formError, 'Why.');
            Assert.areEqual(2, outcome.lineProblems.size(), 'Each refused line is named.');
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift survives the rollback.');
            Assert.areEqual(
                'Open',
                [SELECT Status__c FROM Gift_Batch__c WHERE Id = :tuesday.Id].Status__c,
                'The batch is still open, as it was left.'
            );
        }
    }

    @IsTest
    static void aLineDatedInAClosedPeriodRollsTheWholeBatchBack() {
        fund('General', true);
        Date closed = Date.today().toStartOfMonth().addDays(-1);
        GivingTestDataFactory.closeBooksThrough(closed);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Gift_Batch__c tuesday = batch(150, null, null);
            tuesday.Default_Gift_Date__c = Date.today();
            update tuesday;
            Gift_Batch_Row__c late = line(tuesday.Id, ana.Id, null, 100);
            late.Gift_Date__c = closed.addDays(-2);
            insert new List<Gift_Batch_Row__c>{ late, line(tuesday.Id, ana.Id, null, 50) };

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isFalse(outcome.success, 'The post fails.');
            Assert.areEqual(1, outcome.lineProblems.size(), 'Only the late line is named.');
            Assert.areEqual(late.Id, outcome.lineProblems[0].rowId);
            Assert.isTrue(
                outcome.lineProblems[0].message.startsWith('The books are closed through'),
                outcome.lineProblems[0].message
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift survives the rollback.');
        }
    }

    @IsTest
    static void twoHundredLinesPostInOneGo() {
        fund('General', true);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Gift_Batch__c yearEnd = batch(200 * 25, null, null);
            List<Gift_Batch_Row__c> rows = new List<Gift_Batch_Row__c>();
            for (Integer index = 0; index < 200; index++) {
                rows.add(line(yearEnd.Id, ana.Id, null, 25));
            }
            insert rows;

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(yearEnd.Id);
            Test.stopTest();

            Assert.isTrue(outcome.success, 'A full stack posts: ' + outcome.formError);
            Assert.areEqual(200, outcome.giftCount, 'One gift per line.');
            Assert.areEqual(200, [SELECT COUNT() FROM Gift__c], 'Every gift exists.');
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Gift_Batch_Row__c WHERE Gift__c != NULL],
                'Every line links to its gift.'
            );
        }
    }

    @IsTest
    static void twoHundredLinesWithOneRefusedLineNameItAndPostNothing() {
        // A donor David cannot see: a colleague's contact he has no access to. The platform
        // refuses the one gift that names it, and the partial-success insert retries the other
        // 199, which has to fit in the limits before everything is rolled back.
        fund('General', true);
        User fundraiser = david();
        Contact hidden = new Contact(FirstName = 'Private', LastName = 'Donor');
        insert hidden;
        Gift_Batch__c yearEnd;
        Contact ana;
        System.runAs(fundraiser) {
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Contact WHERE Id = :hidden.Id WITH USER_MODE],
                'Precondition: David cannot see the hidden donor in this org.'
            );
            ana = person();
            yearEnd = batch(200 * 25, null, null);
        }
        List<Gift_Batch_Row__c> rows = new List<Gift_Batch_Row__c>();
        for (Integer index = 0; index < 200; index++) {
            rows.add(line(yearEnd.Id, ana.Id, null, 25));
        }
        rows[136].Donor_Contact__c = hidden.Id;
        insert rows;

        System.runAs(fundraiser) {
            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(yearEnd.Id);
            Test.stopTest();

            Assert.isFalse(outcome.success, 'One refused line stops the post.');
            Assert.areEqual(Label.Giving_GiftBatch_ErrorPostFailed, outcome.formError, 'Why.');
            Assert.areEqual(1, outcome.lineProblems.size(), 'Only the refused line is named.');
            Assert.areEqual(137, outcome.lineProblems[0].lineNumber, 'It is line 137.');
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift survives the rollback.');
        Assert.areEqual(
            'Open',
            [SELECT Status__c FROM Gift_Batch__c WHERE Id = :yearEnd.Id].Status__c,
            'The batch is still open.'
        );
    }

    @IsTest
    static void aPostedBatchPostsOnceAndStaysAsItWas() {
        fund('General', true);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Gift_Batch__c tuesday = batch(100, null, null);
            Gift_Batch_Row__c only = line(tuesday.Id, ana.Id, null, 100);
            insert only;
            Assert.isTrue(GiftBatchService.post(tuesday.Id).success, 'The first post succeeds.');

            Test.startTest();
            GiftBatchService.PostOutcome again = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isFalse(again.success, 'A second post is refused.');
            Assert.areEqual(Label.Giving_GiftBatch_ErrorAlreadyPosted, again.formError, 'Why.');
            Assert.areEqual(1, [SELECT COUNT() FROM Gift__c], 'The deposit is not doubled.');

            tuesday.Control_Total__c = 200;
            Assert.isFalse(Database.update(tuesday, false).isSuccess(), 'The batch is final.');
            only.Amount__c = 200;
            Assert.isFalse(Database.update(only, false).isSuccess(), 'Its lines are final.');
            Assert.isFalse(
                Database.insert(line(tuesday.Id, ana.Id, null, 5), false).isSuccess(),
                'No line is added to a posted batch.'
            );
        }
    }

    @IsTest
    static void anAdministratorCanReassignAPostedBatchButNotChangeIt() {
        fund('General', true);
        User fundraiser = david();
        Gift_Batch__c tuesday;
        System.runAs(fundraiser) {
            Contact ana = person();
            tuesday = batch(100, null, null);
            insert line(tuesday.Id, ana.Id, null, 100);
            Assert.isTrue(GiftBatchService.post(tuesday.Id).success, 'The batch posts.');
        }

        Test.startTest();
        Database.SaveResult reassigned = Database.update(
            new Gift_Batch__c(Id = tuesday.Id, OwnerId = UserInfo.getUserId()),
            false
        );
        Database.SaveResult edited = Database.update(
            new Gift_Batch__c(Id = tuesday.Id, Description__c = 'Wednesday mail'),
            false
        );
        Test.stopTest();

        Assert.isTrue(reassigned.isSuccess(), 'A departed person\'s batch can change hands.');
        Assert.areEqual(
            UserInfo.getUserId(),
            [SELECT OwnerId FROM Gift_Batch__c WHERE Id = :tuesday.Id].OwnerId,
            'The new owner holds it.'
        );
        Assert.isFalse(edited.isSuccess(), 'What the batch says stays as it was posted.');
    }

    @IsTest
    static void staffWhoMayOnlyReadAColleaguesBatchCannotPostIt() {
        // GiftBatchWriter writes in system mode but with sharing, so without this refusal a
        // reader would create the gifts and then fail on the batch: refuse first, in words.
        fund('General', true);
        User fundraiser = david();
        User colleague = TestDataFactory.createUser(
            'Priya',
            new List<String>{ 'BarnCRM_Staff', 'Giving_Staff' }
        );
        Gift_Batch__c tuesday;
        System.runAs(fundraiser) {
            Contact ana = person();
            tuesday = batch(100, null, null);
            insert line(tuesday.Id, ana.Id, null, 100);
            insert new Gift_Batch__Share(
                ParentId = tuesday.Id,
                UserOrGroupId = colleague.Id,
                AccessLevel = 'Read'
            );
        }

        System.runAs(colleague) {
            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isFalse(outcome.success, 'Read access is not enough to post.');
            Assert.areEqual(Label.Giving_GiftBatch_ErrorNoAccess, outcome.formError, 'Why.');
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift was created.');
        Assert.areEqual(
            'Open',
            [SELECT Status__c FROM Gift_Batch__c WHERE Id = :tuesday.Id].Status__c,
            'The batch is still open for its owner.'
        );
    }

    @IsTest
    static void nobodyClosesABatchByHand() {
        User fundraiser = david();

        System.runAs(fundraiser) {
            Gift_Batch__c tuesday = batch(100, null, null);
            tuesday.Status__c = 'Posted';

            Test.startTest();
            Database.SaveResult result = Database.update(tuesday, false, AccessLevel.USER_MODE);
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'Status is written only by posting.');
        }
    }

    @IsTest
    static void deletingAPostedGiftClearsItsLineAndNothingElse() {
        fund('General', true);
        Contact ana = person();
        Gift_Batch__c tuesday = batch(100, null, null);
        Gift_Batch_Row__c only = line(tuesday.Id, ana.Id, null, 100);
        insert only;
        Assert.isTrue(GiftBatchService.post(tuesday.Id).success, 'The batch posts.');
        Gift__c gift = [SELECT Id FROM Gift__c LIMIT 1];

        Test.startTest();
        Database.DeleteResult result = Database.delete(gift, false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'A posted batch does not stop a gift being deleted.');
        Gift_Batch_Row__c after = [
            SELECT Gift__c, Amount__c
            FROM Gift_Batch_Row__c
            WHERE Id = :only.Id
        ];
        Assert.isNull(after.Gift__c, 'The line no longer points at the deleted gift.');
        Assert.areEqual(100, after.Amount__c, 'What the line says was typed is unchanged.');
    }

    /** Ana's pledge of 1,200 in twelve monthly payments of 100 from the batch date. */
    private static List<Installment__c> pledgeOf(Id contactId) {
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = contactId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.newInstance(2026, 3, 14),
            Expected_Total__c = 1200,
            Installments_Planned__c = 12
        );
        insert pledge;
        return [
            SELECT Id, Commitment__c, Expected_Amount__c
            FROM Installment__c
            WHERE Commitment__c = :pledge.Id
            ORDER BY Sequence__c
        ];
    }

    @IsTest
    static void aLineThatPaysAPaymentPostsAGiftThatPaysIt() {
        fund('General', true);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            List<Installment__c> payments = pledgeOf(ana.Id);
            Gift_Batch__c tuesday = batch(100, null, null);
            Gift_Batch_Row__c paying = line(tuesday.Id, ana.Id, null, 100);
            paying.Installment__c = payments[0].Id;
            insert paying;

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isTrue(outcome.success, 'The batch posts: ' + outcome.formError);
            Gift__c gift = [SELECT Installment__c, Commitment__c FROM Gift__c];
            Assert.areEqual(payments[0].Id, gift.Installment__c, 'The gift pays the payment.');
            Assert.areEqual(payments[0].Commitment__c, gift.Commitment__c, 'Of Ana\'s pledge.');
            Assert.areEqual(
                'Paid',
                [SELECT Status__c FROM Installment__c WHERE Id = :payments[0].Id].Status__c,
                'The payment is paid.'
            );
        }
    }

    @IsTest
    static void aLinePayingSomeoneElsesPaymentIsNamedAndNothingPosts() {
        fund('General', true);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            Account riverside = organization();
            List<Installment__c> payments = pledgeOf(ana.Id);
            Gift_Batch__c tuesday = batch(200, null, null);
            Gift_Batch_Row__c honest = line(tuesday.Id, ana.Id, null, 100);
            Gift_Batch_Row__c wrong = line(tuesday.Id, null, riverside.Id, 100);
            wrong.Installment__c = payments[0].Id;
            insert new List<Gift_Batch_Row__c>{ honest, wrong };

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(tuesday.Id);
            Test.stopTest();

            Assert.isFalse(outcome.success, 'The batch does not post.');
            Assert.areEqual(1, outcome.lineProblems.size(), 'One line is wrong.');
            Assert.areEqual(2, outcome.lineProblems[0].lineNumber, 'The second line is named.');
            Assert.areEqual(
                Label.Giving_GiftBatch_ErrorRowPaymentNotOpen,
                outcome.lineProblems[0].message,
                'It says the payment cannot be paid by this line.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'Nothing was created.');
        }
    }

    @IsTest
    static void twoHundredLinesPayingPaymentsPostInOneGo() {
        fund('General', true);
        User fundraiser = david();

        System.runAs(fundraiser) {
            Contact ana = person();
            List<Installment__c> payments = pledgeOf(ana.Id);
            Gift_Batch__c yearEnd = batch(200 * 6, null, null);
            List<Gift_Batch_Row__c> rows = new List<Gift_Batch_Row__c>();
            for (Integer index = 0; index < 200; index++) {
                Gift_Batch_Row__c row = line(yearEnd.Id, ana.Id, null, 6);
                row.Installment__c = payments[Math.mod(index, payments.size())].Id;
                rows.add(row);
            }
            insert rows;

            Test.startTest();
            GiftBatchService.PostOutcome outcome = GiftBatchService.post(yearEnd.Id);
            Test.stopTest();

            Assert.isTrue(outcome.success, 'A full stack posts: ' + outcome.formError);
            Assert.areEqual(
                200,
                [
                    SELECT COUNT()
                    FROM Gift__c
                    WHERE Installment__c != NULL AND Commitment__c != NULL
                ],
                'Every gift pays the payment its line named.'
            );
            Assert.areEqual(
                payments.size(),
                [
                    SELECT COUNT()
                    FROM Installment__c
                    WHERE Commitment__c = :payments[0].Commitment__c AND Status__c != 'Scheduled'
                ],
                'Every payment received something.'
            );
        }
    }
}
