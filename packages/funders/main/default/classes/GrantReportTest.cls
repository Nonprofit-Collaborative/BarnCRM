/**
 * The funder report template (F-06, canonical model 29ZO): the shipped template is copied once and
 * an edited copy is kept (R-FT3), only active templates with a body are offered (R-FT1), and the
 * report data carries the grant's values and requirements for the browser merge.
 */
@IsTest(
    testFor='ApexClass:FunderReportTemplates, ApexClass:GrantReportController, ApexClass:FundersPostInstall'
)
private class GrantReportTest {
    private static final String STAFF = 'Funders_Staff';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(GrantTestData.ADMIN);
        TestUsers.adminWith(STAFF);
    }

    @IsTest
    static void theShippedTemplateIsCopiedOnceAndAnEditIsKept() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            Test.startTest();
            List<Funder_Report_Template__c> first = FunderReportTemplates.installDefaultsDuringInstall();
            Funder_Report_Template__c copied = first[0];
            update as user new Funder_Report_Template__c(Id = copied.Id, Body__c = '<p>Ours</p>');
            List<Funder_Report_Template__c> second = FunderReportTemplates.installDefaultsDuringInstall();
            Test.stopTest();

            Assert.areEqual(1, first.size(), 'One shipped template');
            Assert.areEqual('Grant_Report', copied.Template_Key__c, 'Keyed by its default');
            Assert.isTrue(copied.Active__c, 'Active');
            Assert.isTrue(copied.Body__c.contains('{RequirementTable}'), 'With the tokens');
            Assert.isTrue(second.isEmpty(), 'Not copied twice');
            Assert.areEqual(
                '<p>Ours</p>',
                [
                    SELECT Body__c
                    FROM Funder_Report_Template__c
                    WHERE Id = :copied.Id
                    WITH SYSTEM_MODE
                ]
                .Body__c,
                'The edit is kept'
            );
        }
    }

    @IsTest
    static void staffGetTheGrantAndActiveTemplates() {
        Grant__c grant;
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            FunderReportTemplates.installDefaultsDuringInstall();
            insert as user new Funder_Report_Template__c(
                Name = 'Retired',
                Body__c = '<p>x</p>',
                Active__c = false
            );
            Account funder = GrantTestData.funder('Lakeside Foundation');
            grant = GrantTestData.grant('Reading <Grant>', funder.Id, GrantService.STAGE_AWARDED);
            grant.Amount_Awarded__c = 25000;
            grant.Award_Start_Date__c = Date.newInstance(2026, 1, 1);
            grant.Award_End_Date__c = Date.newInstance(2026, 12, 31);
            grant.Award_Number__c = 'S287C250001';
            insert as user grant;
            insert as user GrantTestData.requirement(
                'Final report',
                grant.Id,
                Date.newInstance(2027, 1, 31)
            );
        }
        System.runAs(TestUsers.adminWith(STAFF)) {
            Test.startTest();
            GrantReportController.ReportData data = GrantReportController.getReportData(grant.Id);
            Test.stopTest();

            Assert.areEqual(1, data.templates.size(), 'Only the active template');
            Assert.areEqual('Grant report', data.templates[0].get('name'), 'The shipped one');
            Assert.areEqual(
                'Reading <Grant>',
                data.grant.get('GrantName'),
                'Raw: the browser escapes'
            );
            Assert.areEqual('Lakeside Foundation', data.grant.get('FunderName'), 'Funder');
            Assert.areEqual(25000, (Decimal) data.grant.get('AmountAwarded'), 'Amount');
            Assert.areEqual('S287C250001', data.grant.get('AwardNumber'), 'Award number');
            Assert.isNotNull(data.grant.get('OrganizationName'), 'An organization name');
            Assert.areEqual(1, data.requirements.size(), 'The requirement');
            Assert.areEqual('Final report', data.requirements[0].get('name'), 'By name');
            Assert.areEqual(5, data.requirementLabels.size(), 'A heading per column');
            Assert.isTrue(data.outcomes.isEmpty(), 'No linked outcome');
            Assert.isNotNull(data.currencyCode, 'A currency');
        }
    }

    @IsTest
    static void aGrantThePersonCannotSeeGivesNothing() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            FunderReportTemplates.installDefaultsDuringInstall();
            Account funder = GrantTestData.funder('Lakeside Foundation');
            Grant__c grant = GrantTestData.grant('Gone', funder.Id, GrantService.STAGE_PROSPECT);
            insert as user grant;
            Id gone = grant.Id;
            delete as user grant;

            Test.startTest();
            GrantReportController.ReportData data = GrantReportController.getReportData(gone);
            Test.stopTest();

            Assert.isTrue(data.templates.isEmpty(), 'No template offered');
            Assert.isTrue(data.grant.isEmpty(), 'No grant');
        }
    }
}
