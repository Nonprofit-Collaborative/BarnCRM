/**
 * Proves the whole path, end to end, in an org where both packages are installed (G-20
 * follow-up, ADR-0053, ADR-0057): Core's `HealthCheckService.run()` finds
 * `GivingHealthCheckExtension` by name, calls it, and folds its finding into the one report
 * Health Check shows. `HealthCheckGivingChecksTest` covers what the finding says; this class
 * covers only that Core actually reaches it.
 */
@IsTest
private class GivingHealthCheckExtensionTest {
    private static User jen() {
        return TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'Nonprofit_Admin', 'Giving_Admin' }
        );
    }

    /**
     * `HealthCheckService.Finding.key` is `@AuraEnabled` only, not `@NamespaceAccessible`, so
     * under a future namespace prefix this package cannot read it directly. A JSON round trip
     * reaches it the same way the real Lightning wire path does.
     */
    private static Map<String, Object> asMap(HealthCheckService.Finding finding) {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(finding));
    }

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        Gift__c gift = GivingTestDataFactory.buildGift(ana.Id, 250);
        gift.Gift_Date__c = Date.today().toStartOfMonth().addDays(-1);
        insert gift;
    }

    @IsTest
    static void delegatesStraightToTheGivingChecks() {
        // Nobody holds the receipt lock override and no receipt run failed, whatever the test
        // org holds, so the one finding counted is the closed period one.
        HealthCheckGivingChecks.holdersOverride = new CustomPermissionSelector.Holders();
        ReceiptGenerationFailureSelector.resultOverride = new ReceiptGenerationFailureSelector.Result();
        // Closing the books is Maria's own act on the Accounting Periods page, done here as
        // the test-running admin: GivingTestDataFactory writes the protected custom setting
        // directly, which is a test-only shortcut around AccountingPeriodWriter's system-mode
        // door (ADR-0021) and needs more than Jen's packaged permission sets grant.
        GivingTestDataFactory.closeBooksThrough(Date.today().toStartOfMonth().addDays(-1));
        User jen = jen();
        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = new GivingHealthCheckExtension().findings();

            System.assertEquals(1, findings.size());
            System.assertEquals('unposted_gifts_closed_period', asMap(findings[0]).get('key'));
        }
    }

    @IsTest
    static void coresOneReportCarriesTheGivingFindingWhenBothPackagesAreInstalled() {
        GivingTestDataFactory.closeBooksThrough(Date.today().toStartOfMonth().addDays(-1));
        User jen = jen();
        System.runAs(jen) {
            List<HealthCheckService.Finding> findings = HealthCheckService.run();

            HealthCheckService.Finding giving = null;
            for (HealthCheckService.Finding finding : findings) {
                if ('unposted_gifts_closed_period'.equals(asMap(finding).get('key'))) {
                    giving = finding;
                }
            }
            System.assertNotEquals(
                null,
                giving,
                'Core resolves the installed extension by name and reports what it finds, ' +
                'without Core ever naming a gift or a closed period itself.'
            );
        }
    }
}
