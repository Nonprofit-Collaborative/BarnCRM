/**
 * The first of the three tests ADR-0016 names: **a number is allocated once and never reused.**
 *
 * Everything about receipt numbering exists to make one question answerable: what happened to
 * number N. These tests are that question asked three ways.
 */
@IsTest(testFor='ApexClass:ReceiptNumberSequence')
private class ReceiptNumberSequenceTest {
    private static final Integer YEAR = 2026;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ReceiptTestDataFactory.setUpReceipting();
        }
    }

    /**
     * Consecutive allocations strictly increase. Not "are different": increase, in order, with no
     * value repeated and none going backwards.
     */
    @IsTest
    static void consecutiveAllocationsStrictlyIncrease() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            List<String> allocated = new List<String>();
            for (Integer index = 0; index < 5; index++) {
                allocated.add(
                    ReceiptNumberSequence.allocateOne(ReceiptNumberSequence.TYPE_PER_GIFT, YEAR)
                );
            }
            Test.stopTest();

            Assert.areEqual(
                'HFH-2026-000001',
                allocated[0],
                'The series starts at the counter in settings.'
            );
            Set<String> unique = new Set<String>(allocated);
            Assert.areEqual(5, unique.size(), 'No number is ever handed out twice.');
            for (Integer index = 1; index < allocated.size(); index++) {
                Assert.isTrue(
                    counterOf(allocated[index]) > counterOf(allocated[index - 1]),
                    'Each number is larger than the one before it: ' +
                        allocated[index - 1] +
                        ' then ' +
                        allocated[index]
                );
            }
        }
    }

    /**
     * A block taken by a batch chunk and a single number taken afterwards do not overlap. This is
     * the case that produces two donors holding the same receipt number if the sequence is wrong,
     * which is the one failure nobody can recover from.
     */
    @IsTest
    static void blockAllocationDoesNotOverlapALaterSingleAllocation() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            List<String> block = ReceiptNumberSequence.allocate(
                ReceiptNumberSequence.TYPE_STATEMENT,
                YEAR,
                25
            );
            String afterwards = ReceiptNumberSequence.allocateOne(
                ReceiptNumberSequence.TYPE_STATEMENT,
                YEAR
            );
            Test.stopTest();

            Assert.areEqual(25, block.size(), 'A block of twenty five is twenty five numbers.');
            Assert.areEqual(25, new Set<String>(block).size(), 'A block contains no repeats.');
            Assert.isFalse(
                new Set<String>(block).contains(afterwards),
                'The number taken after the block is not one of the block: ' + afterwards
            );
            Assert.areEqual(
                counterOf(block[block.size() - 1]) + 1,
                counterOf(afterwards),
                'The next number continues from the end of the block.'
            );
        }
    }

    /**
     * A number that a failed generation consumed is reconciled into a Void receipt and is **not**
     * handed out again. An auditor asking about it finds a record saying the document was never
     * produced, which is an answer; silence is not.
     */
    @IsTest
    static void aNumberConsumedByAFailedGenerationIsReconciledIntoAVoidReceipt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<String> consumed = ReceiptNumberSequence.allocate(
                ReceiptNumberSequence.TYPE_STATEMENT,
                YEAR,
                3
            );
            // The middle document is the one that made it to a record. The other two are numbers that
            // were handed out to a chunk that then failed.
            Contact donor = GivingTestDataFactory.insertHouseholdContact(
                'The Reyes Family',
                'Ana',
                'Reyes'
            );
            insert new Receipt__c(
                Receipt_Number__c = consumed[1],
                Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
                Status__c = ReceiptService.STATUS_ISSUED,
                Statement_Year__c = YEAR,
                Donor_Contact__c = donor.Id,
                Total_Amount__c = 250,
                Issue_Date__c = Date.today(),
                Series_Key__c = ReceiptNumberSequence.seriesKeyFor(
                    ReceiptNumberSequence.TYPE_STATEMENT,
                    YEAR
                )
            );

            Test.startTest();
            Integer accountedFor = ReceiptNumberSequence.reconcile(
                ReceiptNumberSequence.TYPE_STATEMENT,
                YEAR,
                null
            );
            String next = ReceiptNumberSequence.allocateOne(
                ReceiptNumberSequence.TYPE_STATEMENT,
                YEAR
            );
            Test.stopTest();

            Assert.areEqual(2, accountedFor, 'The two numbers with no receipt are accounted for.');

            Map<String, Receipt__c> byNumber = new Map<String, Receipt__c>();
            for (Receipt__c receipt : [
                SELECT Receipt_Number__c, Status__c, Void_Reason__c, Voided_On__c
                FROM Receipt__c
            ]) {
                byNumber.put(receipt.Receipt_Number__c, receipt);
            }

            for (String consumedNumber : new List<String>{ consumed[0], consumed[2] }) {
                Receipt__c reconciled = byNumber.get(consumedNumber);
                Assert.isNotNull(
                    reconciled,
                    'Number ' + consumedNumber + ' has a record, not silence.'
                );
                Assert.areEqual(ReceiptService.STATUS_VOID, reconciled.Status__c, 'It is void.');
                Assert.areEqual(
                    ReceiptNumberSequence.VOID_REASON_GENERATION_FAILED,
                    reconciled.Void_Reason__c,
                    'It says why: the document was never produced.'
                );
                Assert.isNotNull(reconciled.Voided_On__c, 'It says when it was accounted for.');
            }

            Assert.areEqual(
                ReceiptService.STATUS_ISSUED,
                byNumber.get(consumed[1]).Status__c,
                'Reconciliation leaves a surviving receipt alone.'
            );
            Assert.isFalse(
                new Set<String>(consumed).contains(next),
                'A reconciled number is never handed out again: ' + next
            );
        }
    }

    /**
     * The invariant that accounts for the per gift series, asserted rather than assumed.
     *
     * Nothing reconciles the per gift series: `reconcile` runs from `ReceiptStatementBatch.finish`
     * for the statement series and from nowhere else. What accounts for a per gift number is that
     * the allocation and the receipt live in one transaction, so a failed generation rolls the
     * allocation back and no number is consumed at all. This test is that sentence: a rendering
     * failure leaves the counter exactly where it was and no receipt behind. A future caller that
     * catches the failure and commits anyway breaks it, which is why the code says so at
     * `ReceiptService.issueForGift`, `ReceiptNumberSequence.allocateOne` and
     * `ReceiptController.issue`.
     */
    @IsTest
    static void aFailedPerGiftIssueRollsItsNumberBackRatherThanLeavingItUnaccountedFor() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ReceiptService.issuePermission = true;
            ReceiptRendererFactory.overrideRenderer = new ReceiptTestDataFactory.FailingRenderer();
            Contact donor = GivingTestDataFactory.insertHouseholdContact(
                'The Okafor Family',
                'Ada',
                'Okafor'
            );
            Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                donor.Id,
                120,
                Date.newInstance(YEAR, 3, 4)
            );
            insert gift;

            String key = ReceiptNumberSequence.seriesKeyFor(
                ReceiptNumberSequence.TYPE_PER_GIFT,
                YEAR
            );
            // One good allocation first, so there is a series row to compare against.
            ReceiptNumberSequence.allocateOne(ReceiptNumberSequence.TYPE_PER_GIFT, YEAR);
            Decimal before = nextCounterOf(key);

            Test.startTest();
            System.Savepoint beforeIssue = Database.setSavepoint();
            try {
                ReceiptService.issueForGift(gift.Id);
                Assert.fail('A receipt was issued although the renderer failed.');
            } catch (Exception generationFailed) {
                // The caller lets the failure end the transaction. Rolling back to the savepoint is
                // this test standing in for that, since a test method catching an exception does not
                // otherwise undo the DML that ran before it.
                Database.rollback(beforeIssue);
            }
            Test.stopTest();

            Assert.areEqual(
                before,
                nextCounterOf(key),
                'The counter is where it was: a failed issue consumes no number, which is what makes ' +
                'a series with no reconciliation pass answerable.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Receipt__c WHERE Gift__c = :gift.Id],
                'No receipt survives the failure, so there is no number to account for.'
            );
            Assert.isNull(
                [SELECT Receipt_Number__c FROM Gift__c WHERE Id = :gift.Id].Receipt_Number__c,
                'The gift is left unreceipted and unlocked, so the person can simply try again.'
            );
        }
    }

    /** Where the series has got to, read from the row rather than from a returned value. */
    private static Decimal nextCounterOf(String key) {
        return [
            SELECT Next_Counter__c
            FROM Receipt_Number_Sequence__c
            WHERE Series_Key__c = :key
            LIMIT 1
        ]
        .Next_Counter__c;
    }

    /** The counter part of a formatted number, so a test can compare two of them. */
    private static Integer counterOf(String receiptNumber) {
        return Integer.valueOf(receiptNumber.substringAfterLast('-'));
    }
}
