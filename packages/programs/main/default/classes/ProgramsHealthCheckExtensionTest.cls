/**
 * The Programs Health Check finding: open enrollments in a program that has ended, by Status or
 * by End Date, counted and linked; nothing for a viewer who may not manage settings or while the
 * module is turned off; and Core's report finds the extension by name.
 */
@IsTest(testFor='ApexClass:ProgramsHealthCheckExtension')
private class ProgramsHealthCheckExtensionTest {
    private static final String ADMIN = 'Programs_Admin';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith(
            'Hcstaff',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
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

    /** Two open enrollments in ended programs, and one open in a running program. */
    private static void enrollmentsInEndedPrograms() {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
        Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Rivera');
        insert ana;
        Program__c completed = new Program__c(Name = 'Summer Reading', Status__c = 'Completed');
        Program__c pastEnd = new Program__c(
            Name = 'Winter Coats',
            Start_Date__c = Date.today().addDays(-60),
            End_Date__c = Date.today().addDays(-1)
        );
        Program__c running = new Program__c(Name = 'Tutoring');
        insert new List<Program__c>{ completed, pastEnd, running };
        insert new List<Enrollment__c>{
            new Enrollment__c(Program__c = completed.Id, Contact__c = ana.Id),
            new Enrollment__c(Program__c = pastEnd.Id, Contact__c = ana.Id, Stage__c = 'Applied'),
            new Enrollment__c(Program__c = running.Id, Contact__c = ana.Id)
        };
    }

    @IsTest
    static void openEnrollmentsInEndedProgramsAreCountedAndLinked() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            enrollmentsInEndedPrograms();

            Test.startTest();
            Map<String, Object> finding = byKey(new ProgramsHealthCheckExtension().findings())
                .get(ProgramsHealthCheckExtension.KEY);
            Test.stopTest();

            Assert.isNotNull(finding, 'The open enrollments are reported.');
            Assert.areEqual(
                String.format(
                    Label.Programs_HealthCheck_OpenAfterEndTitle,
                    new List<Object>{ '2' }
                ),
                finding.get('title'),
                'Only the two in ended programs count.'
            );
            Assert.areEqual(HealthCheckService.SEVERITY_INFO, finding.get('severity'));
            Assert.areEqual(2, ((List<Object>) finding.get('links')).size(), 'Each is linked.');
        }
    }

    @IsTest
    static void oneAndMoreThanTheCapReadNaturally() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            enrollmentsInEndedPrograms();
            ProgramsHealthCheckExtension.countCap = 1;

            Map<String, Object> capped = byKey(new ProgramsHealthCheckExtension().findings())
                .get(ProgramsHealthCheckExtension.KEY);
            Assert.areEqual(
                String.format(
                    Label.Programs_HealthCheck_OpenAfterEndTitle,
                    new List<Object>{
                        String.format(Label.Programs_HealthCheck_MoreThan, new List<Object>{ '1' })
                    }
                ),
                capped.get('title'),
                'A count past the cap says more than.'
            );

            delete [SELECT Id FROM Enrollment__c WHERE Stage__c = 'Applied'];
            ProgramsHealthCheckExtension.countCap = 1000;
            Map<String, Object> one = byKey(new ProgramsHealthCheckExtension().findings())
                .get(ProgramsHealthCheckExtension.KEY);
            Assert.areEqual(Label.Programs_HealthCheck_OpenAfterEndTitleOne, one.get('title'));
        }
    }

    @IsTest
    static void coresReportCarriesTheProgramsFinding() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            enrollmentsInEndedPrograms();

            Map<String, Map<String, Object>> all = byKey(HealthCheckService.run());

            Assert.isTrue(
                all.containsKey(ProgramsHealthCheckExtension.KEY),
                'Core finds the Programs extension by name.'
            );
        }
    }

    @IsTest
    static void noFindingForAViewerWhoMayNotManageSettingsOrWhileTurnedOff() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            enrollmentsInEndedPrograms();
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Modules_Turned_Off__c = ProgramsAccessSync.MODULE_NAME;
            TestDataFactory.saveSettings(settings);

            Assert.isTrue(
                new ProgramsHealthCheckExtension().findings().isEmpty(),
                'Nothing is reported while Programs is turned off.'
            );
        }
        System.runAs(TestUsers.standardUserWith(
            'Hcstaff',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        )) {
            Assert.isTrue(
                new ProgramsHealthCheckExtension().findings().isEmpty(),
                'A viewer who may not manage settings is asked nothing.'
            );
        }
    }
}
