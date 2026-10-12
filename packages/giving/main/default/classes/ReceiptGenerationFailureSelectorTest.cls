/**
 * ReceiptGenerationFailureSelector counts the void receipts a failed run left behind (R-RC3). The findings
 * built from the count are tested in HealthCheckGivingChecksTest.
 */
@IsTest
private class ReceiptGenerationFailureSelectorTest {
    @IsTest
    static void anOrgWithNoFailedRunsCountsZero() {
        Test.startTest();
        ReceiptGenerationFailureSelector.Result result = ReceiptGenerationFailureSelector.generationFailures();
        Test.stopTest();

        System.assertEquals(true, result.available, 'An administrator can read receipts');
        System.assertEquals(0, result.count, 'Nothing has failed in a fresh org');
    }

    @IsTest
    static void aLongFailureHistoryIsCountedOnlyUpToTheCap() {
        ReceiptTestDataFactory.setUpReceipting();
        List<String> consumed = ReceiptNumberSequence.allocate(
            ReceiptNumberSequence.TYPE_STATEMENT,
            2026,
            3
        );
        ReceiptNumberSequence.reconcile(ReceiptNumberSequence.TYPE_STATEMENT, 2026, null);

        Test.startTest();
        ReceiptGenerationFailureSelector.Result uncapped = ReceiptGenerationFailureSelector.generationFailures();
        ReceiptGenerationFailureSelector.countCap = 2;
        ReceiptGenerationFailureSelector.Result capped = ReceiptGenerationFailureSelector.generationFailures();
        Test.stopTest();

        System.assertEquals(3, consumed.size(), 'Three numbers were handed out and never used');
        System.assertEquals(3, uncapped.count, 'Under the cap, the count is exact');
        System.assertEquals(false, uncapped.capped, 'Under the cap, nothing was cut off');
        System.assertEquals(true, capped.capped, 'Past the cap, counting stops');
        System.assertEquals(2, capped.count, 'Past the cap, the count is the cap');
    }

    @IsTest
    static void aPersonWhoCannotReadReceiptsIsNotToldZero() {
        User nobody = TestDataFactory.createUser('Nobody', new List<String>());

        ReceiptGenerationFailureSelector.Result result;
        Test.startTest();
        System.runAs(nobody) {
            result = ReceiptGenerationFailureSelector.generationFailures();
        }
        Test.stopTest();

        System.assertEquals(
            false,
            result.available,
            'Without read access the question was not answered, which is not the same as zero'
        );
    }
}
