/**
 * Tests for HealthCheckGivingChecks (G-20 follow-up, ADR-0053): the Health Check finding for
 * gifts already locked by a closed period that nothing has marked posted, and the two receipt
 * findings that moved here from Core with C-29 (ADR-0059) with the assertions they had there.
 */
@IsTest
private class HealthCheckGivingChecksTest {
    private static User jen() {
        return TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'Nonprofit_Admin', 'Giving_Admin' }
        );
    }

    private static User david() {
        return TestDataFactory.createUser(
            'David',
            new List<String>{ 'Nonprofit_Staff', 'Giving_Staff' }
        );
    }

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        List<Gift__c> gifts = GivingTestDataFactory.buildGifts(ana.Id, 3, 100);
        for (Integer i = 0; i < gifts.size(); i++) {
            gifts[i].Gift_Date__c = Date.today().toStartOfMonth().addDays(-1 - i);
        }
        insert gifts;
    }

    private static Date lastClosedDay() {
        return Date.today().toStartOfMonth().addDays(-1);
    }

    /**
     * `HealthCheckService.Finding`'s fields are `@AuraEnabled` only, not
     * `@NamespaceAccessible`, so under a future namespace prefix this package cannot read them
     * directly. Reading through a JSON round trip is how the real Lightning wire path reaches
     * them too, so it proves the same thing the direct field reads used to.
     */
    private static Map<String, Object> asMap(HealthCheckService.Finding finding) {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(finding));
    }

    @IsTest
    static void noClosedPeriodFindsNothing() {
        quietReceiptChecks();
        User jen = jen();
        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(
                0,
                findings.size(),
                'With no period closed, nothing in the org is locked yet, so there is nothing ' +
                'to report.'
            );
        }
    }

    @IsTest
    static void viewerWithoutManageSettingsSeesNoFinding() {
        quietReceiptChecks();
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        User david = david();
        System.runAs(david) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(
                0,
                findings.size(),
                'Posting and the close date are an administrator question; a viewer without ' +
                'Manage Nonprofit Settings is skipped rather than answered wrongly.'
            );
        }
    }

    @IsTest
    static void noUnpostedGiftsInClosedPeriodFindsNothing() {
        quietReceiptChecks();
        User jen = jen();
        // Jen must own a gift to mark it posted (ADR-0053: `GiftPostingService.markPosted`
        // reads in user mode, so a gift she cannot see is never touched), but the finding
        // itself reads the whole org without sharing (`HealthCheckGivingSelector`), so every
        // gift anywhere has to actually be posted for this test to see no finding, not only the
        // ones a narrower setup would have given her. Reassigning them to her first is simpler
        // than building a second owner-scoped dataset just to post it.
        Set<Id> giftIds = new Map<Id, Gift__c>([SELECT Id FROM Gift__c]).keySet();
        List<Gift__c> reowned = new List<Gift__c>();
        for (Id giftId : giftIds) {
            reowned.add(new Gift__c(Id = giftId, OwnerId = jen.Id));
        }
        update reowned;
        System.runAs(jen) {
            GiftPostingService.markPosted(giftIds);
        }
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(
                0,
                findings.size(),
                'Every gift in the closed period is already posted, so there is nothing to ' +
                'flag.'
            );
        }
    }

    @IsTest
    static void someUnpostedGiftsAreReportedWithLinksAndAFix() {
        quietReceiptChecks();
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        User jen = jen();
        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(1, findings.size(), 'One finding for the three unposted gifts.');
            Map<String, Object> finding = asMap(findings[0]);
            System.assertEquals('unposted_gifts_closed_period', finding.get('key'));
            System.assertEquals(HealthCheckService.SEVERITY_WARNING, finding.get('severity'));
            System.assertEquals(HealthCheckService.CATEGORY_SETTINGS, finding.get('category'));
            String title = (String) finding.get('title');
            System.assert(title.contains('3'), 'The title names the count: ' + title);
            System.assertEquals(
                3,
                ((List<Object>) finding.get('links')).size(),
                'All three unposted gifts are linked, well under the cap.'
            );
            System.assertEquals(
                SettingSections.GIVING,
                finding.get('fixTarget'),
                'The fix opens the Accounting Periods page, in the Giving settings section.'
            );
            System.assertNotEquals(null, finding.get('fixLabel'));
        }
    }

    @IsTest
    static void capExceededReportsMoreThan() {
        quietReceiptChecks();
        Contact ben = GivingTestDataFactory.insertHouseholdContact(
            'The Okafor Family',
            'Ben',
            'Okafor'
        );
        List<Gift__c> more = GivingTestDataFactory.buildGifts(ben.Id, 4, 50);
        for (Integer i = 0; i < more.size(); i++) {
            more[i].Gift_Date__c = lastClosedDay().addDays(-10 - i);
        }
        insert more;
        // Seven gifts total (three from setup, four here): the count cap and the five-link
        // cap are independent, so this proves both without conflating them.
        HealthCheckGivingChecks.countCap = 2;
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        User jen = jen();
        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertEquals(1, findings.size());
            Map<String, Object> finding = asMap(findings[0]);
            String title = (String) finding.get('title');
            System.assert(
                title.contains('More than 2'),
                'The count stops at the cap of 2 and says so rather than counting every row: ' +
                title
            );
            System.assertEquals(
                5,
                ((List<Object>) finding.get('links')).size(),
                'Links stop at the five shown, independent of the (lower) count cap.'
            );
        }
    }

    /**
     * Nobody holds the override and no receipt run failed, whatever the test org holds, so a
     * test about another finding counts only its own.
     */
    private static void quietReceiptChecks() {
        HealthCheckGivingChecks.holdersOverride = holders(true, 0, new List<String>());
        ReceiptGenerationFailureSelector.resultOverride = receipts(true, 0);
    }

    private static CustomPermissionSelector.Holders holders(
        Boolean readable,
        Integer total,
        List<String> names
    ) {
        CustomPermissionSelector.Holders result = new CustomPermissionSelector.Holders();
        result.readable = readable;
        result.total = total;
        result.names = names;
        return result;
    }

    private static ReceiptGenerationFailureSelector.Result receipts(
        Boolean available,
        Integer count
    ) {
        ReceiptGenerationFailureSelector.Result result = new ReceiptGenerationFailureSelector.Result();
        result.available = available;
        result.count = count;
        return result;
    }

    private static Map<String, Object> findByKey(
        List<HealthCheckService.Finding> findings,
        String key
    ) {
        for (HealthCheckService.Finding finding : findings) {
            Map<String, Object> fields = asMap(finding);
            if (fields.get('key') == key) {
                return fields;
            }
        }
        return null;
    }

    @IsTest
    static void someoneHoldingTheReceiptLockOverrideIsNamed() {
        HealthCheckGivingChecks.holdersOverride = holders(
            true,
            1,
            new List<String>{ 'Dana Ellery' }
        );
        User jen = jen();
        System.runAs(jen) {
            Map<String, Object> finding = findByKey(
                HealthCheckGivingChecks.findings(),
                'override_receipt_lock'
            );

            System.assertNotEquals(null, finding, 'ADR-0024: a standing override is reported.');
            System.assert(
                ((String) finding.get('detail')).contains('Dana Ellery'),
                'The finding names the holder.'
            );
            System.assertEquals(HealthCheckService.SEVERITY_WARNING, finding.get('severity'));
            System.assertEquals(HealthCheckService.CATEGORY_ACCESS, finding.get('category'));
            System.assertEquals(
                HealthCheckService.FIX_CUSTOM_PERMISSIONS_URL,
                finding.get('fixTarget'),
                'The fix is in Setup, deliberately not in the settings console (ADR-0024).'
            );
        }
    }

    @IsTest
    static void severalHoldersAreNamedAndTheRestAreCounted() {
        HealthCheckGivingChecks.holdersOverride = holders(
            true,
            5,
            new List<String>{ 'Ada Lo', 'Ben Ruiz', 'Cara Nkemdi' }
        );
        User jen = jen();
        System.runAs(jen) {
            String detail = (String) findByKey(
                    HealthCheckGivingChecks.findings(),
                    'override_receipt_lock'
                )
                .get('detail');

            System.assert(detail.contains('Cara Nkemdi'), 'The named holders are in the line.');
            System.assert(detail.contains('2'), 'The two past the naming limit are counted.');
        }
    }

    @IsTest
    static void anOverrideNobodyHoldsOrNobodyCanSeeIsNotReported() {
        User jen = jen();
        System.runAs(jen) {
            HealthCheckGivingChecks.holdersOverride = holders(true, 0, new List<String>());
            System.assertEquals(
                null,
                findByKey(HealthCheckGivingChecks.findings(), 'override_receipt_lock'),
                'Granted to nobody is the shipped state, and not a finding.'
            );
            HealthCheckGivingChecks.holdersOverride = holders(false, 0, new List<String>());
            System.assertEquals(
                null,
                findByKey(HealthCheckGivingChecks.findings(), 'override_receipt_lock'),
                'An unanswered question is not reported as a clean bill of health.'
            );
        }
    }

    @IsTest
    static void theOverrideIsNotAskedOfSomeoneWhoCannotSeeOtherPeople() {
        HealthCheckGivingChecks.holdersOverride = holders(
            true,
            1,
            new List<String>{ 'Dana Ellery' }
        );
        User david = david();
        System.runAs(david) {
            System.assertEquals(
                null,
                findByKey(HealthCheckGivingChecks.findings(), 'override_receipt_lock'),
                'Salesforce shows a person only their own access, so only an administrator is asked.'
            );
        }
    }

    @IsTest
    static void oneReceiptNumberConsumedByAFailedRunIsInformation() {
        ReceiptGenerationFailureSelector.resultOverride = receipts(true, 1);
        User jen = jen();
        System.runAs(jen) {
            Map<String, Object> finding = findByKey(
                HealthCheckGivingChecks.findings(),
                'receipt_generation_failed_once'
            );

            System.assertNotEquals(null, finding, 'R-RC3: the reconciliation record is reported.');
            System.assertEquals(HealthCheckService.SEVERITY_INFO, finding.get('severity'));
            System.assertEquals(HealthCheckService.CATEGORY_SETTINGS, finding.get('category'));
            System.assertEquals(ErrorLogCountSelector.listViewUrl(), finding.get('fixTarget'));
        }
    }

    @IsTest
    static void repeatedReceiptFailuresAreAWarningThatSaysHowManyToEveryone() {
        ReceiptGenerationFailureSelector.resultOverride = receipts(true, 9);
        User david = david();
        System.runAs(david) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();
            Map<String, Object> finding = findByKey(findings, 'receipt_generation_failed');

            System.assertNotEquals(
                null,
                finding,
                'Receipt generation is asked of every viewer, as it was in Core.'
            );
            System.assertEquals(HealthCheckService.SEVERITY_WARNING, finding.get('severity'));
            System.assert(
                ((String) finding.get('title')).contains('9'),
                'The title says how many.'
            );
            System.assertEquals(
                null,
                findByKey(findings, 'receipt_generation_failed_once'),
                'Only one of the two receipt findings is ever reported.'
            );
        }
    }

    @IsTest
    static void pastTheCapTheReceiptFindingSaysMoreThan() {
        ReceiptGenerationFailureSelector.Result failures = receipts(true, 1000);
        failures.capped = true;
        ReceiptGenerationFailureSelector.resultOverride = failures;
        User jen = jen();
        System.runAs(jen) {
            Map<String, Object> finding = findByKey(
                HealthCheckGivingChecks.findings(),
                'receipt_generation_failed'
            );
            String expected = String.format(
                Label.Giving_HealthCheck_ReceiptFailedMoreThan,
                new List<Object>{ (1000).format() }
            );
            System.assert(
                ((String) finding.get('title')).startsWith(expected),
                'A capped count is reported as more than the cap.'
            );
        }
    }

    @IsTest
    static void oneGivingCheckThatThrowsDoesNotHideTheOthers() {
        quietReceiptChecks();
        // Names left null make the holder sentence throw, a real failure inside one check.
        HealthCheckGivingChecks.holdersOverride = holders(true, 2, null);
        ReceiptGenerationFailureSelector.resultOverride = receipts(true, 9);
        User jen = jen();
        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckGivingChecks.findings();

            System.assertNotEquals(
                null,
                findByKey(findings, 'check_failed_override_receipt_lock'),
                'The check that threw is reported as failed, by its own key.'
            );
            System.assertEquals(
                null,
                findByKey(findings, 'override_receipt_lock'),
                'The check that threw has no finding of its own.'
            );
            System.assertNotEquals(
                null,
                findByKey(findings, 'receipt_generation_failed'),
                'The other Giving checks still report.'
            );
        }
    }

    @IsTest
    static void noFailedOrUnreadableReceiptsMeansNoFinding() {
        User jen = jen();
        System.runAs(jen) {
            ReceiptGenerationFailureSelector.resultOverride = receipts(true, 0);
            System.assertEquals(
                null,
                findByKey(HealthCheckGivingChecks.findings(), 'receipt_generation_failed_once'),
                'An org whose receipts all generated has nothing to be told.'
            );
            ReceiptGenerationFailureSelector.resultOverride = receipts(false, 0);
            System.assertEquals(
                null,
                findByKey(HealthCheckGivingChecks.findings(), 'receipt_generation_failed_once'),
                'A count nobody could take is not reported as zero.'
            );
        }
    }

    @IsTest
    static void theReceiptLockOverrideShipsGrantedToNobody() {
        CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(
            GiftService.OVERRIDE_RECEIPT_LOCK_PERMISSION
        );

        System.assertEquals(
            0,
            holders.total,
            'ADR-0024: the package ships Override Receipt Lock on no permission set and in no ' +
            'permission set group, so a freshly deployed org has no holders.'
        );
        System.assertEquals(true, holders.readable, 'And the question was answerable.');
    }
}
