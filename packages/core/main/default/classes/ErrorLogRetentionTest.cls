/**
 * Error Log retention (R-E6, ADMIN-26): the daily Error Log run deletes entries older than the
 * setting, whatever their status, and 0 keeps every entry.
 */
@IsTest(testFor='ApexClass:ErrorLogRetention')
private class ErrorLogRetentionTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static List<Error_Log__c> entries(Integer count, String status) {
        List<Error_Log__c> created = new List<Error_Log__c>();
        for (Integer i = 0; i < count; i++) {
            created.add(
                new Error_Log__c(
                    Timestamp__c = System.now(),
                    Context__c = 'Retention test',
                    Message__c = 'The Garcia household could not be renamed.',
                    Severity__c = ErrorLogger.SEVERITY_ERROR,
                    Status__c = status
                )
            );
        }
        insert created;
        return created;
    }

    private static void age(List<Error_Log__c> logs, Integer days) {
        for (Error_Log__c log : logs) {
            Test.setCreatedDate(log.Id, System.now().addDays(-days));
        }
    }

    private static void keepFor(Integer days) {
        BarnCRM_Settings__c record = BarnCRM_Settings__c.getOrgDefaults();
        record.Error_Log_Retention_Days__c = days;
        TestDataFactory.saveSettings(record);
    }

    private static Integer remaining() {
        // Only this test's entries, so an entry the run itself logs cannot change the count.
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Context__c = 'Retention test'
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void entriesPastTheDefaultAreDeletedWhateverTheirStatus() {
        System.runAs(TestUsers.admin()) {
            List<Error_Log__c> old = entries(50, ErrorLogger.STATUS_NEW);
            old.addAll(entries(50, ErrorLogger.STATUS_RESOLVED));
            age(old, ErrorLogRetention.DEFAULT_DAYS + 1);
            entries(100, ErrorLogger.STATUS_NEW);

            Test.startTest();
            Id job = ErrorLogRetention.start();
            Test.stopTest();

            Assert.isNotNull(job, 'The delete runs as a batch');
            Assert.areEqual(100, remaining(), 'The 100 older than 180 days are gone, New or not');
        }
    }

    @IsTest
    static void theSettingDecidesHowLongEntriesAreKept() {
        System.runAs(TestUsers.admin()) {
            keepFor(30);
            age(entries(3, ErrorLogger.STATUS_NEW), 40);
            age(entries(2, ErrorLogger.STATUS_NEW), 20);

            Test.startTest();
            ErrorLogRetention.start();
            Test.stopTest();

            Assert.areEqual(30, ErrorLogRetention.retentionDays(), 'Thirty days, as saved');
            Assert.areEqual(2, remaining(), 'Only the entries from the last 30 days are kept');
        }
    }

    @IsTest
    static void zeroKeepsEveryEntry() {
        System.runAs(TestUsers.admin()) {
            keepFor(0);
            age(entries(3, ErrorLogger.STATUS_NEW), 4000);

            Test.startTest();
            Id job = ErrorLogRetention.start();
            Test.stopTest();

            Assert.isNull(job, 'Nothing is started');
            Assert.areEqual(3, remaining(), 'and every entry is kept');
        }
    }

    @IsTest
    static void theDailyErrorLogRunDeletesOldEntries() {
        System.runAs(TestUsers.admin()) {
            age(entries(2, ErrorLogger.STATUS_IGNORED), ErrorLogRetention.DEFAULT_DAYS + 1);
            entries(1, ErrorLogger.STATUS_NEW);
            ErrorDigestService.emailSender = new RecordingEmailSender();

            Test.startTest();
            new ErrorDigestScheduler().execute(null);
            Test.stopTest();

            Assert.areEqual(1, remaining(), 'The morning run deleted the two old entries');
        }
    }
}
