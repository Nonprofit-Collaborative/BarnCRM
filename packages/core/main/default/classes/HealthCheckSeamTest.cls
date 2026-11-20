/**
 * Core's side of Health Check on its own (ADR-0233): each of Core's fix keys pressed through
 * `HealthCheckFixes.applyForModules`, a module's fix through `HealthCheckFixExtension`, the
 * refusals, and the report vocabulary `HealthCheckService` gives the Org Optimizer module. None
 * of it needs that module's runner, so these hold on an org with Core alone. Fixes run as Maria,
 * who may manage settings; the refusal is asserted as Priya.
 */
@IsTest(testFor='ApexClass:HealthCheckFixes, ApexClass:HealthCheckService')
private class HealthCheckSeamTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static final String STUB_FIX_KEY = 'restoreStubThings';
	private static final String STUB_FIX_LABEL = 'Restore stub things';

	/** A module's extension with one finding and one fix, which writes a change of its own. */
	private class StubFixer implements HealthCheckExtension, HealthCheckFixExtension {
		public List<String> missing = new List<String>{ 'Stub thing' };

		public List<HealthCheckService.Finding> findings() {
			if (missing.isEmpty()) {
				return new List<HealthCheckService.Finding>();
			}
			return new List<HealthCheckService.Finding>{
				new HealthCheckService.Finding(
						'stub_things_missing',
						'Stub things are missing',
						String.join(missing, ', '),
						HealthCheckService.SEVERITY_WARNING,
						HealthCheckService.CATEGORY_SETTINGS
					)
					.withScope(new List<String>(missing))
					.withFix(STUB_FIX_LABEL, HealthCheckService.FIX_ACTION_PREFIX + STUB_FIX_KEY)
			};
		}

		public List<String> fixScope(String fixKey) {
			return STUB_FIX_KEY.equals(fixKey) ? new List<String>(missing) : null;
		}

		public String fixLabel(String fixKey) {
			return STUB_FIX_KEY.equals(fixKey) ? STUB_FIX_LABEL : null;
		}

		public String runFix(String fixKey, List<String> scope) {
			SettingsService.logChange('Stub fix ran', '', String.join(scope, ', '));
			missing.clear();
			return 'Created ' + String.join(scope, ', ') + '.';
		}
	}

	/** An extension whose findings throw, as a broken module's might. */
	private class ThrowingExtension implements HealthCheckExtension {
		public List<HealthCheckService.Finding> findings() {
			throw new IllegalArgumentException('Broken extension');
		}
	}

	/** The Org Optimizer module's runner, stood in for. */
	private class StubRun implements HealthCheckRun {
		public List<HealthCheckService.Finding> findings() {
			return new List<HealthCheckService.Finding>{
				new HealthCheckService.Finding(
					'stub_run',
					'Title',
					'Detail',
					HealthCheckService.SEVERITY_INFO,
					HealthCheckService.CATEGORY_ORG_SHAPE
				)
			};
		}
	}

	/** Sees the org as having no module extension, so no test depends on what is installed. */
	private static void noExtensions() {
		HealthCheckExtensions.noneForTest = true;
	}

	private static StubFixer installStubFixer() {
		StubFixer fixer = new StubFixer();
		noExtensions();
		HealthCheckExtensions.overrides.put('RollupsHealthCheckExtension', fixer);
		return fixer;
	}

	/** Presses a Core fix with the scope it has now, as the panel does with a fresh finding. */
	private static HealthCheckService.Report press(String fixKey) {
		return HealthCheckFixes.applyForModules(fixKey, HealthCheckService.fixScope(fixKey));
	}

	private static void assertRefusedAsStale(String fixKey, List<String> scope) {
		try {
			HealthCheckFixes.applyForModules(fixKey, scope);
			Assert.fail('A fix whose scope no longer matches the org is refused.');
		} catch (AuraHandledException expected) {
			Assert.areEqual(
				System.Label.Core_HealthCheck_FixStale,
				expected.getMessage(),
				'Refused with the sentence that says the org changed since the scan.'
			);
		}
	}

	private static Integer changesLogged(String fixLabel) {
		return [
			SELECT COUNT()
			FROM Setting_Change__c
			WHERE Setting_Name__c = :('Health Check: ' + fixLabel)
			WITH SYSTEM_MODE
		];
	}

	/** A user who has left: inactive, so a job they own has stopped running. */
	private static Id inactiveUserId() {
		User gone = new User(
			FirstName = 'Former',
			LastName = 'Scheduler',
			Alias = 'formsch',
			Email = 'former.scheduler.barncrm@example.com',
			Username = 'former.scheduler.barncrm.' + Datetime.now().getTime() + '@example.com',
			ProfileId = TestUsers.standardProfileId(),
			TimeZoneSidKey = 'America/New_York',
			LocaleSidKey = 'en_US',
			EmailEncodingKey = 'UTF-8',
			LanguageLocaleKey = 'en_US',
			IsActive = false
		);
		insert gone;
		return gone.Id;
	}

	/** Cancels the BarnCRM jobs the org already has, so a test names only the ones it made. */
	private static void clearOrgBarnCrmJobs() {
		for (CronTrigger job : [
			SELECT Id
			FROM CronTrigger
			WHERE CronJobDetail.Name LIKE 'BarnCRM%'
			WITH SYSTEM_MODE
		]) {
			System.abortJob(job.Id);
		}
		ScheduledJobSelector.forget();
	}

	@IsTest
	static void missingAutomationSwitchesAreRestoredOnce() {
		System.runAs(TestUsers.admin()) {
			User maria = HealthCheckTestHelper.mariaWithManageSettings();
			noExtensions();
			AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
				TestDataFactory.registryEntry('Test_Household_Naming', true),
				TestDataFactory.registryEntry('Test_Address_Sync', true)
			};
			String fixKey = HealthCheckService.FIX_KEY_RESTORE_AUTOMATION_SWITCHES;

			System.runAs(maria) {
				List<String> scope = HealthCheckService.fixScope(fixKey);
				Assert.areEqual(2, scope.size(), 'Two automations have no switch.');

				Test.startTest();
				HealthCheckService.Report report = HealthCheckFixes.applyForModules(fixKey, scope);
				assertRefusedAsStale(fixKey, scope);
				Test.stopTest();

				Assert.isTrue(report.getFixOutcome().contains('Test Address Sync'), report.getFixOutcome());
				Assert.isTrue(HealthCheckService.fixScope(fixKey).isEmpty(), 'Every switch is back.');
				Assert.areEqual(1, changesLogged(System.Label.Core_HealthCheck_SwitchesMissingFix), 'Recorded once.');
			}
			Assert.areEqual(2, [SELECT COUNT() FROM Automation_Setting__c], 'One switch each, none twice.');
		}
	}

	@IsTest
	static void missingImportTemplatesAreRestoredOnce() {
		System.runAs(TestUsers.admin()) {
			User maria = HealthCheckTestHelper.mariaWithManageSettings();
			noExtensions();
			String fixKey = HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES;

			System.runAs(maria) {
				List<String> scope = HealthCheckService.fixScope(fixKey);
				Assert.isFalse(scope.isEmpty(), 'Core ships import templates, and a test org starts without any.');

				Test.startTest();
				HealthCheckService.Report report = HealthCheckFixes.applyForModules(fixKey, scope);
				assertRefusedAsStale(fixKey, scope);
				Test.stopTest();

				Assert.isNotNull(report.getFixOutcome(), 'Says what it created.');
				Assert.areEqual(scope.size(), [SELECT COUNT() FROM Import_Template__c], 'Pressing twice is once.');
			}
		}
	}

	@IsTest
	static void unscheduledNightlyJobsAreScheduled() {
		System.runAs(TestUsers.admin()) {
			User maria = HealthCheckTestHelper.mariaWithManageSettings();
			noExtensions();
			clearOrgBarnCrmJobs();
			String fixKey = HealthCheckService.FIX_KEY_SCHEDULE_NIGHTLY_JOBS;

			System.runAs(maria) {
				Assert.isFalse(HealthCheckService.fixScope(fixKey).isEmpty(), 'Nothing is scheduled yet.');

				// No startTest: the scheduled run must not execute inside the test.
				HealthCheckService.Report report = press(fixKey);

				Assert.isTrue(
					report.getFixOutcome().contains(System.Label.Core_NightlyJobs_Title),
					report.getFixOutcome()
				);
				ScheduledJobSelector.forget();
				Assert.isTrue(HealthCheckService.fixScope(fixKey).isEmpty(), 'Nothing is left unscheduled.');
				Assert.areEqual(1, changesLogged(System.Label.Core_HealthCheck_NightlyJobsFix), 'Recorded.');
			}
		}
	}

	@IsTest
	static void jobsOfADeactivatedOwnerAreScheduledAgainOrStopped() {
		System.runAs(TestUsers.admin()) {
			User maria = HealthCheckTestHelper.mariaWithManageSettings();
			noExtensions();
			Id gone = inactiveUserId();
			String otherJob = 'BarnCRM Fix test job';
			clearOrgBarnCrmJobs();
			NightlyJobs.start();
			ScheduledJobSelector.schedule(otherJob, '0 0 3 * * ?', new ErrorDigestScheduler());
			ScheduledJobSelector.overrideOwnerForTest(gone);
			ScheduledJobSelector.forget();
			String fixKey = HealthCheckService.FIX_KEY_RESCHEDULE_INACTIVE_OWNER_JOBS;

			System.runAs(maria) {
				List<String> scope = HealthCheckService.fixScope(fixKey);
				Assert.isTrue(scope.contains(otherJob), 'The job of the deactivated owner is named.');

				// No startTest: the scheduled run must not execute inside the test.
				HealthCheckService.Report report = HealthCheckFixes.applyForModules(fixKey, scope);

				Assert.isTrue(report.getFixOutcome().contains(NightlyJobs.jobName()), report.getFixOutcome());
				Assert.isTrue(
					report.getFixOutcome()
						.contains(
							String.format(
								BarnHelp.text('Core', 'Core_HealthCheck_FixStoppedOnly'),
								new List<Object>{ otherJob }
							)
						),
					'A job it never schedules is said to be stopped only: ' + report.getFixOutcome()
				);
				Assert.areEqual(1, changesLogged(System.Label.Core_HealthCheck_InactiveOwnerJobsFix), 'Recorded.');
			}
			ScheduledJobSelector.overrideOwnerForTest(null);
			ScheduledJobSelector.forget();
			Assert.isNull(ScheduledJobSelector.triggerIdByName(otherJob), 'The unknown job was stopped.');
			Assert.isNotNull(ScheduledJobSelector.triggerIdByName(NightlyJobs.jobName()), 'The known job runs again.');
		}
	}

	@IsTest
	static void unfilledMatchKeysStartTheFill() {
		System.runAs(TestUsers.admin()) {
			User maria = HealthCheckTestHelper.mariaWithManageSettings();
			noExtensions();
			AddressMatchKeyBatch.unfilledForTest = true;
			String fixKey = HealthCheckService.FIX_KEY_FILL_MATCH_KEYS;

			System.runAs(maria) {
				List<String> scope = HealthCheckService.fixScope(fixKey);
				Assert.areEqual(1, scope.size(), 'One fill to start.');

				Test.startTest();
				HealthCheckService.Report report = HealthCheckFixes.applyForModules(fixKey, scope);
				Test.stopTest();

				Assert.areEqual(
					BarnHelp.text('Core', 'Core_HealthCheck_MatchKeysStarted'),
					report.getFixOutcome(),
					'Says the fill has started.'
				);
			}
		}
	}

	@IsTest
	static void aModulesFixRunsAndAFailureAfterWritingLeavesNothing() {
		System.runAs(TestUsers.admin()) {
			User maria = HealthCheckTestHelper.mariaWithManageSettings();
			StubFixer fixer = installStubFixer();

			System.runAs(maria) {
				List<String> scope = HealthCheckService.fixScope(STUB_FIX_KEY);
				Integer changesBefore = [SELECT COUNT() FROM Setting_Change__c WITH SYSTEM_MODE];
				HealthCheckFixes.failAfterFixForTest(true);
				try {
					HealthCheckFixes.applyForModules(STUB_FIX_KEY, scope);
					Assert.fail('The failure after the fix is reported.');
				} catch (AuraHandledException expected) {
					Assert.isNotNull(expected.getMessage(), 'With a sentence.');
				}
				Assert.areEqual(
					changesBefore,
					[SELECT COUNT() FROM Setting_Change__c WITH SYSTEM_MODE],
					'Rolled back, history included.'
				);

				HealthCheckFixes.failAfterFixForTest(false);
				fixer.missing = new List<String>{ 'Stub thing' };
				HealthCheckService.Report report = HealthCheckFixes.applyForModules(STUB_FIX_KEY, scope);
				Assert.areEqual('Created Stub thing.', report.getFixOutcome(), 'The module says what it did.');
				Assert.isTrue(report.getFindings().isEmpty(), 'Read again, nothing is missing.');
				Assert.areEqual(1, changesLogged(STUB_FIX_LABEL), 'Recorded under its button label.');
			}
		}
	}

	@IsTest
	static void anUnknownFixOrAPersonWithoutThePermissionIsRefused() {
		System.runAs(TestUsers.admin()) {
			User maria = HealthCheckTestHelper.mariaWithManageSettings();
			User priya = HealthCheckTestHelper.priyaWithoutManageSettings();
			noExtensions();

			System.runAs(maria) {
				Assert.isNull(HealthCheckService.fixScope('deleteEverything'), 'Not a fix Health Check has.');
				Assert.isNull(HealthCheckService.fixOwner(null), 'No key, no owner.');
				try {
					HealthCheckFixes.applyForModules('deleteEverything', new List<String>());
					Assert.fail('An unknown fix is refused.');
				} catch (AuraHandledException expected) {
					Assert.areEqual(
						BarnHelp.text('Core', 'Core_HealthCheck_FixUnknown'),
						expected.getMessage(),
						'Refused with a sentence.'
					);
				}
			}
			System.runAs(priya) {
				try {
					HealthCheckFixes.apply(HealthCheckService.FIX_KEY_RESTORE_IMPORT_TEMPLATES, new List<String>());
					Assert.fail('Priya may not change settings.');
				} catch (AuraHandledException expected) {
					Assert.areEqual(
						BarnHelp.text('Core', 'Core_HealthCheck_PermissionRequired'),
						expected.getMessage(),
						'Refused with a sentence.'
					);
				}
			}
			Assert.areEqual(0, [SELECT COUNT() FROM Import_Template__c], 'Nothing was created.');
		}
	}

	@IsTest
	static void theReportIsFilledByFieldNameAndReadByItsGetters() {
		System.runAs(TestUsers.admin()) {
			OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
			List<HealthCheckService.Finding> findings = new List<HealthCheckService.Finding>{
				new HealthCheckService.Finding('k', 'T', 'D', HealthCheckService.SEVERITY_ERROR, 'Access')
			};
			HealthCheckService.Report report = new HealthCheckService.Report()
				.put('findings', findings)
				.put('skippedChecks', new List<String>{ 'later' })
				.put('canManageSettings', true)
				.put('orgShape', shape)
				.put('orgShapeSummary', 'Summary')
				.put('currentMode', CoexistenceService.MODE_NPSP)
				.put('currentModeLabel', 'NPSP label')
				.put('recommendedMode', CoexistenceService.MODE_STANDALONE)
				.put('recommendedModeLabel', 'Standalone label')
				.put('modeNeedsAttention', true)
				.put('fixOutcome', 'Done');

			Assert.areEqual(findings, report.getFindings(), 'findings');
			Assert.areEqual(new List<String>{ 'later' }, report.getSkippedChecks(), 'skippedChecks');
			Assert.isTrue(report.getCanManageSettings(), 'canManageSettings');
			Assert.areEqual(shape, report.getOrgShape(), 'orgShape');
			Assert.areEqual('Summary', report.getOrgShapeSummary(), 'orgShapeSummary');
			Assert.areEqual(CoexistenceService.MODE_NPSP, report.getCurrentMode(), 'currentMode');
			Assert.areEqual('NPSP label', report.currentModeLabel, 'currentModeLabel');
			Assert.areEqual(CoexistenceService.MODE_STANDALONE, report.getRecommendedMode(), 'recommendedMode');
			Assert.areEqual('Standalone label', report.getRecommendedModeLabel(), 'recommendedModeLabel');
			Assert.isTrue(report.getModeNeedsAttention(), 'modeNeedsAttention');
			Assert.areEqual('Done', report.getFixOutcome(), 'fixOutcome');
			Assert.areEqual(NamespaceUtil.qualify(HealthCheckService.SETTINGS_TAB), report.settingsTabApiName, 'Tab');
			try {
				report.put('nothing', 'x');
				Assert.fail('An unknown field is refused.');
			} catch (IllegalArgumentException expected) {
				Assert.isTrue(expected.getMessage().contains('nothing'), 'Naming the field.');
			}
		}
	}

	@IsTest
	static void aFindingCarriesItsFixScopeAndLinks() {
		System.runAs(TestUsers.admin()) {
			User me = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE];
			HealthCheckService.Link link = new HealthCheckService.Link(me);
			HealthCheckService.Finding finding = new HealthCheckService.Finding(
					'key',
					'Title',
					'Detail',
					HealthCheckService.SEVERITY_WARNING,
					HealthCheckService.CATEGORY_LICENSES
				)
				.withFix('Fix', HealthCheckService.FIX_ACTION_PREFIX + 'x')
				.withScope(new List<String>{ 'a' })
				.withLinks(new List<HealthCheckService.Link>{ link });

			Assert.areEqual('key', finding.getKey(), 'key');
			Assert.areEqual('Title', finding.getTitle(), 'title');
			Assert.areEqual('Detail', finding.getDetail(), 'detail');
			Assert.areEqual(HealthCheckService.SEVERITY_WARNING, finding.getSeverity(), 'severity');
			Assert.areEqual(HealthCheckService.CATEGORY_LICENSES, finding.getCategory(), 'category');
			Assert.areEqual('action:x', finding.getFixTarget(), 'fix target');
			Assert.areEqual(new List<String>{ 'a' }, finding.getFixScope(), 'fix scope');
			Assert.areEqual(me.Name, finding.getLinks()[0].getLabel(), 'link label');
			Assert.areEqual('/lightning/r/User/' + me.Id + '/view', finding.getLinks()[0].getUrl(), 'link url');
			Assert.areEqual(
				'1 thing',
				HealthCheckService.forCount(1, '{0} thing', '{0} things', new List<Object>{ 1 }),
				'one'
			);
			Assert.areEqual(
				'2 things',
				HealthCheckService.forCount(2, '{0} thing', '{0} things', new List<Object>{ 2 }),
				'many'
			);
		}
	}

	@IsTest
	static void aBrokenExtensionBecomesOneFindingAndTheRunnerIsOptional() {
		System.runAs(TestUsers.admin()) {
			noExtensions();
			HealthCheckExtensions.overrides.put('GivingHealthCheckExtension', new ThrowingExtension());
			HealthCheckService.loggerFault = new IllegalArgumentException('Logger down');

			List<HealthCheckService.Finding> findings = HealthCheckService.extensionFindings();
			Assert.areEqual(1, findings.size(), 'One finding stands in for the failure.');
			Assert.areEqual('check_failed_giving_extension', findings[0].getKey(), 'Named by its extension.');
			Assert.isTrue(
				HealthCheckService.extensionFindings(new List<String>(), new Set<String>{ 'other' }).isEmpty(),
				'Limited to other keys, it is not run.'
			);
			List<String> skipped = new List<String>{ 'earlier' };
			HealthCheckService.extensionFindings(skipped, null);
			Assert.isTrue(skipped.contains('giving_extension'), 'Once a run has stopped, the rest are skipped.');
			Assert.isFalse(HealthCheckService.nearLimits(), 'A small test is far from the limits.');

			for (
				String mode : new List<String>{
					CoexistenceService.MODE_NONPROFIT_CLOUD,
					CoexistenceService.MODE_NPSP,
					CoexistenceService.MODE_STANDALONE,
					null
				}
			) {
				Assert.isNotNull(HealthCheckService.modeLabel(mode), 'Every mode has a name: ' + mode);
			}

			ModuleExtensions.stubForTest(HealthCheckRun.class, 'OrgOptimizer', new StubRun(), true);
			Assert.areEqual('stub_run', HealthCheckService.runInstalled()[0].getKey(), 'The runner, when installed.');
		}
	}
}
