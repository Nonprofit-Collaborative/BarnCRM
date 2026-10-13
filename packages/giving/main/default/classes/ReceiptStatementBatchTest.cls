/**
 * The year end run: one statement per donor, resumable, and reconciled when it closes.
 */
@IsTest(testFor='ApexClass:ReceiptStatementBatch')
private class ReceiptStatementBatchTest {
    private static final Integer YEAR = 2026;

    /**
     * A run issues one statement per donor, whatever the number of gifts, and the run record says
     * what it did.
     */
    @IsTest
    static void aRunIssuesOneStatementPerDonorAndRecordsWhatItDid() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Contact reyes = GivingTestDataFactory.insertHouseholdContact(
                    'The Reyes Family',
                    'Ana',
                    'Reyes'
                );
                Contact osei = GivingTestDataFactory.insertHouseholdContact(
                    'The Osei Family',
                    'Kofi',
                    'Osei'
                );
                insert new List<Gift__c>{
                    ReceiptTestDataFactory.plainCashGift(
                        reyes.Id,
                        100,
                        Date.newInstance(YEAR, 2, 1)
                    ),
                    ReceiptTestDataFactory.plainCashGift(
                        reyes.Id,
                        150,
                        Date.newInstance(YEAR, 8, 1)
                    ),
                    ReceiptTestDataFactory.plainCashGift(osei.Id, 400, Date.newInstance(YEAR, 5, 1))
                };

                Receipt_Run__c run = new Receipt_Run__c(
                    Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
                    Statement_Year__c = YEAR,
                    Status__c = ReceiptRunService.STATUS_QUEUED,
                    Donors_Processed__c = 0,
                    Receipts_Issued__c = 0,
                    Errors__c = 0
                );
                insert run;

                Test.startTest();
                Database.executeBatch(
                    new ReceiptStatementBatch(YEAR, run.Id),
                    ReceiptStatementBatch.SCOPE
                );
                Test.stopTest();

                List<Receipt__c> issued = [
                    SELECT
                        Id,
                        Receipt_Number__c,
                        Total_Amount__c,
                        Donor_Account__c,
                        Donor_Year_Key__c,
                        Status__c
                    FROM Receipt__c
                    WHERE Type__c = :ReceiptNumberSequence.TYPE_STATEMENT AND Status__c = 'Issued'
                ];
                Assert.areEqual(
                    2,
                    issued.size(),
                    'Two households gave, so two statements were issued.'
                );

                Map<Id, Decimal> totalByDonor = new Map<Id, Decimal>();
                for (Receipt__c receipt : issued) {
                    totalByDonor.put(receipt.Donor_Account__c, receipt.Total_Amount__c);
                    Assert.isNotNull(
                        receipt.Donor_Year_Key__c,
                        'Each statement carries the key that makes a rerun safe.'
                    );
                }
                Assert.areEqual(
                    250,
                    totalByDonor.get(reyes.AccountId),
                    'A household statement totals the household year.'
                );
                Assert.areEqual(
                    400,
                    totalByDonor.get(osei.AccountId),
                    'The other household totals its own year.'
                );

                Receipt_Run__c finished = [
                    SELECT
                        Status__c,
                        Donors_Processed__c,
                        Receipts_Issued__c,
                        Errors__c,
                        Finished__c
                    FROM Receipt_Run__c
                    WHERE Id = :run.Id
                ];
                Assert.areEqual(
                    ReceiptRunService.STATUS_COMPLETED,
                    finished.Status__c,
                    'A run with no failed chunk ends Completed.'
                );
                Assert.areEqual(2, finished.Receipts_Issued__c, 'The run counted what it issued.');
                Assert.areEqual(0, finished.Errors__c, 'Nothing failed.');
                Assert.isNotNull(finished.Finished__c, 'The run says when it ended.');
            }

        }
    }

    /**
     * Running again does not send a donor a second statement. This is what makes a run that died
     * halfway resumable rather than dangerous (R-RR2).
     */
    @IsTest
    static void runningAgainDoesNotIssueASecondStatementToTheSameDonor() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            System.runAs(ReceiptTestDataFactory.issuer()) {
                ReceiptTestDataFactory.setUpReceipting();
                Contact reyes = GivingTestDataFactory.insertHouseholdContact(
                    'The Reyes Family',
                    'Ana',
                    'Reyes'
                );
                Gift__c gift = ReceiptTestDataFactory.plainCashGift(
                    reyes.Id,
                    100,
                    Date.newInstance(YEAR, 2, 1)
                );
                insert gift;

                Receipt_Run__c first = new Receipt_Run__c(
                    Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
                    Statement_Year__c = YEAR,
                    Status__c = ReceiptRunService.STATUS_QUEUED,
                    Donors_Processed__c = 0,
                    Receipts_Issued__c = 0,
                    Errors__c = 0
                );
                Receipt_Run__c second = first.clone(false, true, false, false);
                insert new List<Receipt_Run__c>{ first, second };

                Test.startTest();
                Database.executeBatch(
                    new ReceiptStatementBatch(YEAR, first.Id),
                    ReceiptStatementBatch.SCOPE
                );
                Test.stopTest();

                Database.executeBatch(
                    new ReceiptStatementBatch(YEAR, second.Id),
                    ReceiptStatementBatch.SCOPE
                );

                Assert.areEqual(
                    1,
                    [
                        SELECT COUNT()
                        FROM Receipt__c
                        WHERE
                            Type__c = :ReceiptNumberSequence.TYPE_STATEMENT
                            AND Status__c = 'Issued'
                            AND Donor_Account__c = :reyes.AccountId
                    ],
                    'The donor holds one statement for the year, not two.'
                );
            }

        }
    }

    /** Starting a run from the console writes a record even before the batch has done anything. */
    @IsTest
    static void startingARunLeavesARecordBehindImmediately() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ReceiptTestDataFactory.setUpReceipting();

            Test.startTest();
            Receipt_Run__c run = ReceiptRunService.startStatementRun(YEAR);
            Test.stopTest();

            Receipt_Run__c stored = [
                SELECT Type__c, Statement_Year__c, Status__c, Async_Job_Id__c
                FROM Receipt_Run__c
                WHERE Id = :run.Id
            ];
            Assert.areEqual(YEAR, stored.Statement_Year__c, 'The run knows which year it covers.');
            Assert.areEqual(
                ReceiptNumberSequence.TYPE_STATEMENT,
                stored.Type__c,
                'The run knows what it generates.'
            );
            Assert.isNotNull(
                stored.Async_Job_Id__c,
                'The run names the job, so a stuck one can be found.'
            );
        }
    }
}
