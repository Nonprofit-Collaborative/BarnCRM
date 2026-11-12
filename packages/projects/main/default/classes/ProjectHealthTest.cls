/**
 * R-PM2: the nightly step and Refresh Health set On Track, At Risk or Off Track with the reasons,
 * for Active projects that are not templates only, and the settings tune the thresholds.
 */
@IsTest(testFor='ApexClass:ProjectHealth, ApexClass:ProjectsSettings')
private class ProjectHealthTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static Project__c read(Id projectId) {
		return [
			SELECT Health__c, Health_Reasons__c
			FROM Project__c
			WHERE Id = :projectId
			WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void theNightlyStepSetsHealthByTheRule() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c onTrack = ProjectsTestData.project('Active', null);
			ProjectsTestData.task(onTrack.Id, 'Late by a day', Date.today().addDays(-1), false);
			Project__c lateTask = ProjectsTestData.project('Active', null);
			ProjectsTestData.task(lateTask.Id, 'Data mapping', Date.today().addDays(-7), false);
			Project__c lateMilestone = ProjectsTestData.project('Active', null);
			ProjectsTestData.task(lateMilestone.Id, 'Go-Live', Date.today().addDays(-1), true);
			Project__c pastTarget = ProjectsTestData.project('Active', null);
			pastTarget.Target_Date__c = Date.today().addDays(-1);
			Project__c planned = ProjectsTestData.project('Planned', null);
			planned.Health__c = 'At Risk';
			update new List<Project__c>{ pastTarget, planned };

			Test.startTest();
			new ProjectHealth().execute(null);
			Test.stopTest();

			Assert.areEqual(
				'On Track',
				read(onTrack.Id).Health__c,
				'One day late is under the 7 days'
			);
			Project__c risky = read(lateTask.Id);
			Assert.areEqual('At Risk', risky.Health__c, 'Seven days late');
			Assert.isTrue(
				risky.Health_Reasons__c.contains('Data mapping'),
				'The late task is named'
			);
			Assert.areEqual('At Risk', read(lateMilestone.Id).Health__c, 'A late milestone');
			Assert.areEqual('Off Track', read(pastTarget.Id).Health__c, 'Past its target date');
			Assert.isNull(read(planned.Id).Health__c, 'Only an Active project has a health');
		}
	}

	@IsTest
	static void budgetHoursWarnThenPutOffTrack() {
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = ProjectsTestData.project('Active', 10);
			ProjectsTestData.time(project.Id, 9.5, true);

			Test.startTest();
			ProjectsController.refreshHealth(project.Id);
			String near = read(project.Id).Health__c;
			ProjectsTestData.time(project.Id, 1, false);
			ProjectsController.refreshHealth(project.Id);
			Test.stopTest();

			Assert.areEqual('At Risk', near, '95% of the budget hours used');
			Project__c over = read(project.Id);
			Assert.areEqual('Off Track', over.Health__c, 'Over the budget hours');
			Assert.isTrue(over.Health_Reasons__c.contains('10.5'), 'The hours used are named');
		}
	}

	@IsTest
	static void manyProjectsAreCheckedInOneRun() {
		System.runAs(ProjectsTestData.admin()) {
			List<Project__c> projects = new List<Project__c>();
			for (Integer i = 0; i < 200; i++) {
				projects.add(
					new Project__c(
						Name = 'P' + i,
						Type__c = 'Internal',
						Status__c = 'Active',
						Is_Template__c = i == 0
					)
				);
			}
			insert projects;
			List<Project_Task__c> tasks = new List<Project_Task__c>();
			for (Project__c project : projects) {
				tasks.add(
					new Project_Task__c(
						Project__c = project.Id,
						Name = 'Late',
						Status__c = 'In Progress',
						Due_Date__c = Date.today().addDays(-30)
					)
				);
			}
			insert tasks;

			Test.startTest();
			new ProjectHealth().execute(null);
			Test.stopTest();

			Assert.areEqual(
				199,
				[SELECT COUNT() FROM Project__c WHERE Health__c = 'At Risk' WITH SYSTEM_MODE],
				'Every active project but the template'
			);
			Assert.areEqual(7, ProjectsSettings.atRiskDays(), 'Shipped days late before at risk');
			Assert.areEqual(40, ProjectsSettings.weeklyCapacity(), 'Shipped weekly capacity');
			Assert.isTrue(ProjectsSettings.timeTracking(), 'Time tracking ships on');
		}
	}

	@IsTest
	static void staffRefreshAsThemselves() {
		User staffer = ProjectsTestData.staff('Staffer');
		Project__c project;
		System.runAs(ProjectsTestData.admin()) {
			project = ProjectsTestData.project('Active', null);
			ProjectsTestData.task(project.Id, 'Interviews', Date.today().addDays(-10), false);
		}
		System.runAs(staffer) {
			Test.startTest();
			ProjectsController.refreshHealth(project.Id);
			Test.stopTest();
			Assert.areEqual(
				'At Risk',
				read(project.Id).Health__c,
				'Staff can refresh a shared project'
			);
		}
	}
}
