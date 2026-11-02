/**
 * The Funders Health Check finding (R-GN7): open applications past their deadline, counted and
 * linked; nothing for a viewer who may not manage settings; and Core's report finds the
 * extension by name.
 */
@IsTest(testFor='ApexClass:FundersHealthCheckExtension')
private class FundersHealthCheckExtensionTest {
    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(GrantTestData.ADMIN);
        TestUsers.standardUserWith(
            'Hcfunders',
            new List<String>{ 'BarnCRM_Read_Only', 'Funders_Read_Only' }
        );
    }

    /** `Finding.key` is `@AuraEnabled` only, so it is read through JSON. */
    private static Map<String, Map<String, Object>> byKey(
        List<HealthCheckService.Finding> findings
    ) {
        Map<String, Map<String, Object>> result = new Map<String, Map<String, Object>>();
        for (HealthCheckService.Finding finding : findings) {
            Map<String, Object> fields = (Map<String, Object>) JSON.deserializeUntyped(
                JSON.serialize(finding)
            );
            result.put((String) fields.get('key'), fields);
        }
        return result;
    }

    /** Two open applications past their deadline, one in time, one applied and one declined. */
    private static void grants() {
        Account funder = GrantTestData.funder('Lakeside Foundation');
        Date yesterday = Date.today().addDays(-1);
        List<Grant__c> grants = new List<Grant__c>();
        for (
            String stage : new List<String>{
                GrantService.STAGE_PROSPECT,
                GrantService.STAGE_INVITED,
                GrantService.STAGE_APPLIED,
                GrantService.STAGE_DECLINED
            }
        ) {
            Grant__c grant = GrantTestData.grant(stage, funder.Id, stage);
            grant.Application_Deadline__c = yesterday;
            grants.add(grant);
        }
        Grant__c inTime = GrantTestData.grant('In time', funder.Id, GrantService.STAGE_PROSPECT);
        inTime.Application_Deadline__c = Date.today();
        grants.add(inTime);
        insert grants;
    }

    @IsTest
    static void applicationsPastTheirDeadlineAreCountedAndLinked() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            grants();

            Test.startTest();
            Map<String, Object> finding = byKey(new FundersHealthCheckExtension().findings())
                .get(FundersHealthCheckExtension.KEY_PAST_DEADLINE);
            Test.stopTest();

            Assert.isNotNull(finding, 'The late applications are reported.');
            Assert.areEqual(
                String.format(Label.Funders_HealthCheck_PastDeadlineTitle, new List<Object>{ '2' }),
                finding.get('title'),
                'Only the two not yet submitted count.'
            );
            Assert.areEqual(2, ((List<Object>) finding.get('links')).size(), 'Each is linked.');
        }
    }

    @IsTest
    static void oneLateApplicationAndTheCapAreWordedForTheirCount() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            Account funder = GrantTestData.funder('Lakeside Foundation');
            List<Grant__c> two = new List<Grant__c>{
                GrantTestData.grant('A', funder.Id, GrantService.STAGE_PROSPECT),
                GrantTestData.grant('B', funder.Id, GrantService.STAGE_PROSPECT)
            };
            insert two;

            Test.startTest();
            FundersHealthCheckExtension.countCap = 1;
            HealthCheckService.Finding capped = FundersHealthCheckExtension.finding(
                'key',
                two,
                'one',
                Label.Funders_HealthCheck_PastDeadlineTitle,
                'detail'
            );
            HealthCheckService.Finding single = FundersHealthCheckExtension.finding(
                'key',
                new List<Grant__c>{ two[0] },
                'one',
                Label.Funders_HealthCheck_PastDeadlineTitle,
                'detail'
            );
            Test.stopTest();

            Map<String, Object> cappedFields = (Map<String, Object>) JSON.deserializeUntyped(
                JSON.serialize(capped)
            );
            Map<String, Object> singleFields = (Map<String, Object>) JSON.deserializeUntyped(
                JSON.serialize(single)
            );
            Assert.isTrue(
                ((String) cappedFields.get('title'))
                    .contains(
                        String.format(Label.Funders_HealthCheck_MoreThan, new List<Object>{ '1' })
                    ),
                'Past the cap it says more than'
            );
            Assert.areEqual('one', singleFields.get('title'), 'One has its own wording');
        }
    }

    @IsTest
    static void nothingForAViewerWhoCannotManageSettings() {
        User admin = TestUsers.adminWith(GrantTestData.ADMIN);
        System.runAs(admin) {
            grants();
        }
        User staff = [SELECT Id FROM User WHERE LastName = 'Hcfunders' WITH SYSTEM_MODE LIMIT 1];
        System.runAs(staff) {
            Test.startTest();
            List<HealthCheckService.Finding> found = new FundersHealthCheckExtension().findings();
            Test.stopTest();

            Assert.isTrue(found.isEmpty(), 'Only settings managers are asked');
        }
    }

    @IsTest
    static void coreFindsTheExtensionByName() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            Object built = Type.forName('FundersHealthCheckExtension').newInstance();
            Assert.isTrue(built instanceof HealthCheckExtension, 'Core builds it by its name.');
            Assert.isTrue(
                HealthCheckExtensions.EXTENSION_CLASSES.contains('FundersHealthCheckExtension'),
                'Core lists it.'
            );
        }
    }
}
