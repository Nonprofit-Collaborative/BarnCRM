/**
 * The Rollups page of the settings console, from the Apex side.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class RollupControllerTest {
    private static Rollup_Definition__c definition() {
        return new Rollup_Definition__c(
            Name = 'Household member count',
            Definition_Key__c = 'Core_Household_Member_Count',
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    @IsTest
    static void thePageCarriesEveryRollupAndTheFreshnessTheAdminAsksAbout() {
        System.runAs(TestUsers.admin()) {
            insert definition();

            RollupController.RollupPageView page = RollupController.getPage();

            System.Assert.areEqual(1, page.rollups.size(), 'Every rollup is listed');
            System.Assert.areEqual(
                'Household member count',
                page.rollups[0].name,
                'By the name the admin gave it'
            );
            System.Assert.areEqual(
                'Member_Count__c',
                page.rollups[0].targetField,
                'And where the number shows'
            );
            System.Assert.isTrue(
                page.stale,
                'Nothing has been calculated yet, which the page says'
            );
            System.Assert.isTrue(
                page.builderTabApiName.endsWith('Rollup_Builder'),
                'The page links to the Builder tab'
            );
            System.Assert.areEqual(3, page.modes.size(), 'Real time, Scheduled, and Both');
            List<String> modeLabels = new List<String>();
            for (RollupController.ModeOption option : page.modeOptions) {
                modeLabels.add(option.label);
            }
            System.Assert.areEqual(
                new List<String>{ 'Instantly', 'Every night', 'Both (recommended)' },
                modeLabels,
                'R-R4: the admin reads the new names; the stored values are unchanged'
            );
            System.Assert.areEqual(
                RollupService.MODE_REAL_TIME,
                page.modeOptions[0].value,
                'And the value saved is still the stored one'
            );
        }
    }

    @IsTest
    static void switchingARollupOffLeavesTheNumbersAlone() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c rollup = definition();
            insert rollup;

            Test.startTest();
            RollupController.setActive(rollup.Id, false);
            Test.stopTest();

            Rollup_Definition__c saved = [
                SELECT Active__c
                FROM Rollup_Definition__c
                WHERE Id = :rollup.Id
            ];
            System.Assert.isFalse(
                saved.Active__c,
                'R-R6: an admin turns a shipped rollup off rather than deleting it'
            );
        }
    }

    @IsTest
    static void changingTheModeIsSaved() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c rollup = definition();
            insert rollup;

            Test.startTest();
            RollupController.setMode(rollup.Id, RollupService.MODE_SCHEDULED);
            Test.stopTest();

            Rollup_Definition__c saved = [
                SELECT Mode__c
                FROM Rollup_Definition__c
                WHERE Id = :rollup.Id
            ];
            System.Assert.areEqual(
                RollupService.MODE_SCHEDULED,
                saved.Mode__c,
                'The mode the admin chose'
            );
        }
    }

    @IsTest
    static void aModeThatIsNotAModeIsRefusedInPlainLanguage() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c rollup = definition();
            insert rollup;

            try {
                RollupController.setMode(rollup.Id, 'Whenever');
                System.Assert.fail('Only the three modes are modes');
            } catch (AuraHandledException expected) {
                System.Assert.isNotNull(expected.getMessage(), 'The message names the three');
            }
        }
    }

    /** ROLLUPS-8: a year based total cannot be Instantly only, from the list either. */
    @IsTest
    static void aYearBasedTotalCannotBeSwitchedToInstantlyOnly() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c rollup = definition();
            rollup.Fiscal_Year_Aware__c = true;
            rollup.Fiscal_Year_Offset__c = 0;
            rollup.Fiscal_Date_Field__c = 'Start_Date__c';
            insert rollup;

            String message;
            try {
                RollupController.setMode(rollup.Id, RollupService.MODE_REAL_TIME);
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }

            System.Assert.areEqual(Label.Core_RollupBuilder_ErrorInstantMovesWithDate, message);
            System.Assert.areEqual(
                RollupService.MODE_BOTH,
                [SELECT Mode__c FROM Rollup_Definition__c WHERE Id = :rollup.Id].Mode__c,
                'The mode is unchanged'
            );
        }
    }

    @IsTest
    static void recalculatingSomethingThatIsGoneSaysSoRatherThanFailing() {
        System.runAs(TestUsers.admin()) {
            try {
                RollupController.recalculate(null);
                System.Assert.fail('An unknown definition is refused');
            } catch (AuraHandledException expected) {
                System.Assert.isNotNull(
                    expected.getMessage(),
                    'The message tells the admin to refresh'
                );
            }
        }
    }

    @IsTest
    static void restoringDefaultsCreatesTheShippedRollupsThisOrgIsMissing() {
        System.runAs(TestUsers.admin()) {
            RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
                new Rollup_Definition_Default__mdt(
                    DeveloperName = 'Core_Household_Member_Count',
                    MasterLabel = 'Household member count',
                    Definition_Key__c = 'Core_Household_Member_Count',
                    Source_Object__c = 'Household_Member__c',
                    Target_Object__c = 'Account',
                    Relationship_Path__c = 'Household__c',
                    Aggregate__c = 'COUNT',
                    Target_Field__c = 'Member_Count__c',
                    Mode__c = 'Both',
                    Default_Active__c = true,
                    Package__c = 'Core'
                )
            };

            Test.startTest();
            RollupController.RollupPageView page = RollupController.restoreDefaults();
            Test.stopTest();

            System.Assert.areEqual(
                1,
                page.rollups.size(),
                'The shipped rollup is there after restoring'
            );
        }
    }

    // ------------------------------------------------------------- Recalculate all (slice S12)

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    /** The estimate as Maria sees it at this time of day in her own time zone. */
    private static RollupController.FullRunEstimate estimateAt(User admin, Date day, Time hour) {
        RollupController.FullRunEstimate estimate;
        System.runAs(admin) {
            RollupController.estimatedAt = Datetime.newInstance(day, hour);
            estimate = RollupController.estimateFullRun();
        }
        return estimate;
    }

    @IsTest
    static void recalculateAllSaysHowManyRecordsAndHowLong() {
        System.runAs(TestUsers.admin()) {
            insert definition();
            List<Account> accounts = new List<Account>();
            for (Integer i = 0; i < 200; i++) {
                accounts.add(new Account(Name = 'Household ' + i));
            }
            insert accounts;
            User admin = maria();
            Integer records;
            System.runAs(admin) {
                records = [SELECT COUNT() FROM Account WITH USER_MODE];
            }

            Test.startTest();
            RollupController.FullRunEstimate estimate = estimateAt(
                admin,
                Date.newInstance(2026, 10, 12),
                Time.newInstance(10, 0, 0, 0)
            );
            Test.stopTest();

            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_Estimate,
                    new List<String>{ records.format(), (1).format() }
                ),
                estimate.summary,
                'Every account a scheduled rollup writes, at the rough rate'
            );
            System.Assert.isTrue(estimate.workingHours, 'Ten on a Monday morning is working hours');
        }
    }

    @IsTest
    static void eveningsAndWeekendsAreNotWorkingHours() {
        System.runAs(TestUsers.admin()) {
            insert definition();
            User admin = maria();
            Date monday = Date.newInstance(2026, 10, 12);

            Test.startTest();
            Boolean evening = estimateAt(admin, monday, Time.newInstance(18, 0, 0, 0)).workingHours;
            Boolean saturday = estimateAt(admin, monday.addDays(5), Time.newInstance(10, 0, 0, 0))
                .workingHours;
            Boolean early = estimateAt(admin, monday.addDays(1), Time.newInstance(7, 59, 0, 0))
                .workingHours;
            Test.stopTest();

            System.Assert.isFalse(evening, 'Six in the evening is after hours');
            System.Assert.isFalse(saturday, 'Saturday is not a working day');
            System.Assert.isFalse(early, 'Before eight is not working hours');
        }
    }

    @IsTest
    static void runTonightSetsUpOneRunWhenTheNightlyRunIsOff() {
        System.runAs(TestUsers.admin()) {
            RollupScheduler.jobNameInUse = 'BarnCRM Rollups test ' + Crypto.getRandomInteger();
            String first;
            String second;

            Test.startTest();
            System.runAs(maria()) {
                first = RollupController.runTonight();
                second = RollupController.runTonight();
            }
            Test.stopTest();

            String pattern = RollupScheduler.jobNameInUse + ' %';
            System.Assert.areEqual(Label.Core_RollupBuilder_TonightScheduled, first);
            System.Assert.areEqual(Label.Core_RollupBuilder_TonightScheduled, second);
            System.Assert.areEqual(
                1,
                [SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :pattern],
                'Asking twice sets up one run'
            );
            System.Assert.isFalse(
                RollupScheduler.isScheduled(),
                'The nightly run is not turned on'
            );
        }
    }

    @IsTest
    static void runTonightDoesNothingMoreWhenTheNightlyRunIsOn() {
        System.runAs(TestUsers.admin()) {
            RollupScheduler.jobNameInUse = 'BarnCRM Rollups test ' + Crypto.getRandomInteger();
            RollupScheduler.start();
            String notice;

            Test.startTest();
            System.runAs(maria()) {
                notice = RollupController.runTonight();
            }
            Test.stopTest();

            String pattern = RollupScheduler.jobNameInUse + ' %';
            System.Assert.areEqual(Label.Core_RollupBuilder_TonightAlreadyScheduled, notice);
            System.Assert.areEqual(0, [SELECT COUNT() FROM CronJobDetail WHERE Name LIKE :pattern]);
        }
    }

    @IsTest
    static void staffCannotEstimateOrScheduleTonight() {
        System.runAs(TestUsers.admin()) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            List<String> messages = new List<String>();
            System.runAs(david) {
                try {
                    RollupController.estimateFullRun();
                } catch (AuraHandledException refused) {
                    messages.add(refused.getMessage());
                }
                try {
                    RollupController.runTonight();
                } catch (AuraHandledException refused) {
                    messages.add(refused.getMessage());
                }
            }
            System.Assert.areEqual(
                new List<String>{
                    Label.Core_Rollups_ErrorNoPermission,
                    Label.Core_Rollups_ErrorNoPermission
                },
                messages
            );
        }
    }
}
