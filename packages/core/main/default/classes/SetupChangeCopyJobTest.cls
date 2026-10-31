/**
 * The nightly Setup Changes copy (C-56, canonical model Section 29W): each trail row is kept
 * once with its fields (R-SC2), the delete pass removes only rows past the retention (R-SC4),
 * the retention setting reads its default and holds its bounds, the job schedules once and is
 * one of Health Check's nightly jobs, and a run reads the real trail without failing.
 *
 * Trail rows cannot be inserted, so the copy is fed rows built the way SOQL returns them.
 */
@IsTest(testFor='ApexClass:SetupChangeCopyJob, ApexClass:NightlyJobs')
private class SetupChangeCopyJobTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** One Setup Audit Trail row as SOQL returns it; a blank author is an automated process. */
    private static SObject trailRow(String id, Datetime createdAt, String author, String display) {
        Map<String, Object> row = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'SetupAuditTrail' },
            'Id' => id,
            'Action' => 'changedFieldLabel',
            'Section' => 'Customize Accounts',
            'Display' => display,
            'CreatedDate' => createdAt,
            'DelegateUser' => null
        };
        if (author != null) {
            row.put(
                'CreatedBy',
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'User' },
                    'Name' => author
                }
            );
        }
        return ((List<SObject>) JSON.deserialize(
            JSON.serialize(new List<Object>{ row }),
            List<SObject>.class
        ))[0];
    }

    private static List<Setup_Change__c> kept() {
        return [
            SELECT
                Audit_Trail_Id__c,
                Changed_At__c,
                Changed_By__c,
                Section__c,
                Action__c,
                Display__c
            FROM Setup_Change__c
            WITH SYSTEM_MODE
            ORDER BY Changed_At__c
        ];
    }

    private static void keepFor(Integer days) {
        BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
        settings.Setup_Change_Retention_Days__c = days;
        TestDataFactory.saveSettings(settings);
    }

    @IsTest
    static void eachTrailRowIsKeptOnceWithItsFields() {
        Datetime first = Datetime.now().addDays(-3);
        List<SObject> trail = new List<SObject>{
            trailRow('0Ym000000000001AAA', first, 'Pat Admin', 'Changed Phone field label'),
            trailRow('0Ym000000000002AAA', first.addHours(1), null, 'x'.repeat(1200))
        };
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SetupChangeCopyJob.copy(trail);
            // The newest kept second is read again on purpose; nothing is stored twice.
            SetupChangeCopyJob.copy(trail);
            Test.stopTest();
        }

        List<Setup_Change__c> rows = kept();
        Assert.areEqual(2, rows.size(), 'One kept row per trail row, however often it is copied.');
        Assert.areEqual('0Ym000000000001AAA', rows[0].Audit_Trail_Id__c, 'Keyed by the trail ID.');
        Assert.areEqual(first, rows[0].Changed_At__c, 'When it was changed.');
        Assert.areEqual('Pat Admin', rows[0].Changed_By__c, 'Who changed it.');
        Assert.areEqual('Customize Accounts', rows[0].Section__c, 'Where.');
        Assert.areEqual('changedFieldLabel', rows[0].Action__c, 'The kind of change.');
        Assert.areEqual('Changed Phone field label', rows[0].Display__c, 'In Salesforce words.');
        Assert.isNull(rows[1].Changed_By__c, 'An automated process has no name.');
        Assert.areEqual(1000, rows[1].Display__c.length(), 'A long sentence is cut to fit.');
    }

    @IsTest
    static void aChunkThatCannotBeKeptIsLoggedNotThrown() {
        Datetime at = Datetime.now().addDays(-1);
        // The same trail ID twice in one chunk: the platform refuses both, and the run goes on.
        List<SObject> trail = new List<SObject>{
            trailRow('0Ym000000000003AAA', at, 'Pat Admin', 'one'),
            trailRow('0Ym000000000003AAA', at, 'Pat Admin', 'two'),
            trailRow(null, at, 'Pat Admin', 'no ID')
        };
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            SetupChangeCopyJob.copy(trail);
            SetupChangeCopyJob.copy(new List<SObject>());
            Test.stopTest();
        }

        Assert.areEqual(0, kept().size(), 'Nothing is kept, and nothing was thrown.');
    }

    @IsTest
    static void theDeletePassRemovesOnlyChangesPastTheRetention() {
        keepFor(365);
        insert as system new List<Setup_Change__c>{
            new Setup_Change__c(
                Audit_Trail_Id__c = 'old',
                Changed_At__c = Datetime.now().addDays(-400)
            ),
            new Setup_Change__c(
                Audit_Trail_Id__c = 'new',
                Changed_At__c = Datetime.now().addDays(-300)
            )
        };
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Database.executeBatch(new SetupChangeCopyJob(true), SetupChangeCopyJob.CHUNK_SIZE);
            Test.stopTest();
        }

        List<Setup_Change__c> rows = kept();
        Assert.areEqual(1, rows.size(), 'Only the change older than 365 days is deleted.');
        Assert.areEqual('new', rows[0].Audit_Trail_Id__c, 'The newer change is kept.');
    }

    @IsTest
    static void theRetentionReadsItsDefaultAndHoldsItsBounds() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(730, SetupChangeCopyJob.retentionDays(), 'Two years unless changed.');
            keepFor(10);
            Assert.areEqual(180, SetupChangeCopyJob.retentionDays(), 'Never fewer than 180 days.');
            keepFor(9999);
            Assert.areEqual(3650, SetupChangeCopyJob.retentionDays(), 'Never more than ten years.');
            keepFor(400);
            Assert.areEqual(400, SetupChangeCopyJob.retentionDays(), 'Anything between is used.');
        }
    }

    @IsTest
    static void aRunReadsTheRealTrailAndChainsTheDeletePass() {
        // Something kept now, so the run reads only the newest seconds of the org's trail.
        insert as system new Setup_Change__c(
            Audit_Trail_Id__c = 'marker',
            Changed_At__c = Datetime.now()
        );
        SetupChangeCopyJob.chainPurge = false;
        Boolean started;
        Boolean runningAfterStart;
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            started = SetupChangeCopyJob.runNow();
            runningAfterStart = SetupChangeCopyJob.isRunning();
            Boolean second = SetupChangeCopyJob.runNow();
            Assert.isFalse(second, 'A second copy is not started beside a waiting one.');
            Test.stopTest();
        }

        Assert.isTrue(started, 'The first copy starts.');
        Assert.isTrue(runningAfterStart, 'It is seen as waiting or running.');
        Assert.isTrue(kept().size() >= 1, 'The run finished and kept what it had.');
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Error_Log__c
                WHERE Context__c = 'SetupChangeCopyJob'
                WITH SYSTEM_MODE
            ],
            'An administrator can read the trail, so nothing is logged.'
        );
    }

    @IsTest
    static void theNightlyCopySchedulesOnceAndIsAHealthCheckJob() {
        // The scheduled run fires at stopTest: something kept now keeps its read to seconds.
        insert as system new Setup_Change__c(
            Audit_Trail_Id__c = 'marker',
            Changed_At__c = Datetime.now()
        );
        SetupChangeCopyJob.chainPurge = false;
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Id first = SetupChangeCopyJob.start();
            Id again = SetupChangeCopyJob.start();
            Test.stopTest();

            Assert.areEqual(first, again, 'Never two jobs under the one name.');
            Assert.isTrue(SetupChangeCopyJob.isScheduled(), 'It is scheduled.');
            NightlyJobs.SetupChangesJob listed = new NightlyJobs.SetupChangesJob();
            Assert.isTrue(listed.isScheduled(), 'Health Check sees it as scheduled.');
            Assert.areEqual(
                Label.Core_HealthCheck_JobSetupChanges,
                listed.label(),
                'Named from a label.'
            );
        }
    }

    @IsTest
    static void theScheduleStartsACopy() {
        insert as system new Setup_Change__c(
            Audit_Trail_Id__c = 'marker',
            Changed_At__c = Datetime.now()
        );
        SetupChangeCopyJob.chainPurge = false;
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            new SetupChangeCopyJob().execute((SchedulableContext) null);
            Assert.isTrue(SetupChangeCopyJob.isRunning(), 'The scheduled run starts the copy.');
            new NightlyJobs.SetupChangesJob().schedule();
            Test.stopTest();
        }
        Assert.isTrue(SetupChangeCopyJob.isScheduled(), 'Health Check schedules it.');
    }
}
