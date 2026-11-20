/**
 * BarnCRM Connector's recipe clock checks in Health Check (CN-03; canonical model R-CR8; design
 * Section 3.9), asked by `ConnectorHealthCheckExtension`:
 * - a lane with recipe work and no heartbeat (warning, with Open Super Connector to restart it);
 * - Integration User recipes while no integration user is chosen or it is inactive (error), or
 *   it lacks BarnCRM Connections (warning);
 * - runs Queued for more than 30 minutes (warning): a lane that never started, for example a
 *   subscriber change not yet applied with Suspend and Resume;
 * - recipes Paused by Failures (warning) and Active recipes whose Record Owner is inactive
 *   (warning);
 * - Pause All Recipes on (info).
 */
public with sharing class ConnectorClockChecks {
	public static final Integer WAITING_MINUTES = 30;

	public static List<HealthCheckService.Finding> findings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		ConnectorClock.Status clock = ConnectorClock.status();
		Boolean userReady = ConnectorIntegrationUser.ready();
		for (ConnectorClock.Lane lane : clock.lanes) {
			Boolean isUser = lane.lane == ConnectorClock.LANE_USER;
			// A user lane with no ready user is reported below, as the user's problem.
			if (lane.needed && !lane.beating && (!isUser || userReady)) {
				found.add(
					finding(
							'connector_clock_stopped_' + lane.lane.toLowerCase(),
							BarnHelp.text('Connector', 'Connector_Health_ClockStopped_Title'),
							BarnHelp.text(
								'Connector',
								'Connector_Health_ClockStopped_Detail',
								new List<Object>{
									isUser
										? BarnHelp.text('Connector', 'Connector_Lane_IntegrationUser')
										: BarnHelp.text('Connector', 'Connector_Lane_Automation')
								}
							),
							HealthCheckService.SEVERITY_WARNING
						)
						.withFix(
							BarnHelp.text('Connector', 'Connector_Health_OpenConnector'),
							'/lightning/n/' + NamespaceUtil.qualify('Super_Connector')
						)
				);
			}
		}
		found.addAll(integrationUserFindings());
		Integer waiting = ConnectorRunStore.queuedLongerThan(WAITING_MINUTES);
		if (waiting > 0) {
			found.add(
				finding(
					'connector_runs_waiting',
					BarnHelp.text('Connector', 'Connector_Health_RunsWaiting_Title'),
					BarnHelp.text(
						'Connector',
						'Connector_Health_RunsWaiting_Detail',
						new List<Object>{ waiting, WAITING_MINUTES }
					),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
		found.addAll(recipeFindings());
		if (clock.paused) {
			found.add(
				finding(
					'connector_recipes_paused',
					BarnHelp.text('Connector', 'Connector_Health_AllPaused_Title'),
					BarnHelp.text('Connector', 'Connector_Health_AllPaused_Detail'),
					HealthCheckService.SEVERITY_INFO
				)
			);
		}
		return found;
	}

	/** "Integration User inactive" and its kin, only while Integration User recipes are Active. */
	private static List<HealthCheckService.Finding> integrationUserFindings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		List<String> names = new List<String>();
		for (Connector_Recipe__c recipe : [
			SELECT Name
			FROM Connector_Recipe__c
			WHERE Run_As__c = :ConnectorRecipes.RUN_AS_USER AND Status__c = :ConnectorRunStore.ACTIVE
			WITH SYSTEM_MODE
			ORDER BY Name
			LIMIT 50
		]) {
			names.add(recipe.Name);
		}
		if (names.isEmpty()) {
			return found;
		}
		ConnectorIntegrationUser.View chosen = ConnectorIntegrationUser.view();
		String recipes = String.join(names, ', ');
		if (chosen.id == null) {
			found.add(
				finding(
					'connector_integration_user_inactive',
					BarnHelp.text('Connector', 'Connector_Health_UserNotChosen_Title'),
					BarnHelp.text('Connector', 'Connector_Health_UserNotChosen_Detail', new List<Object>{ recipes }),
					HealthCheckService.SEVERITY_ERROR
				)
			);
		} else if (chosen.active != true) {
			found.add(
				finding(
					'connector_integration_user_inactive',
					BarnHelp.text('Connector', 'Connector_Health_UserInactive_Title'),
					BarnHelp.text(
						'Connector',
						'Connector_Health_UserInactive_Detail',
						new List<Object>{ chosen.name, recipes }
					),
					HealthCheckService.SEVERITY_ERROR
				)
			);
		} else if (chosen.hasConnections != true) {
			found.add(
				finding(
					'connector_integration_user_access',
					BarnHelp.text('Connector', 'Connector_Health_UserAccess_Title'),
					BarnHelp.text('Connector', 'Connector_Health_UserAccess_Detail', new List<Object>{ chosen.name }),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
		return found;
	}

	/** Recipes Paused by Failures, and Active recipes whose Record Owner is inactive. */
	private static List<HealthCheckService.Finding> recipeFindings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		List<String> paused = new List<String>();
		Map<Id, List<String>> byOwner = new Map<Id, List<String>>();
		for (Connector_Recipe__c recipe : [
			SELECT Name, Status__c, Record_Owner_Id__c
			FROM Connector_Recipe__c
			WHERE
				Status__c = :ConnectorRunStore.PAUSED_BY_FAILURES
				OR (Status__c = :ConnectorRunStore.ACTIVE
				AND Record_Owner_Id__c != NULL)
			WITH SYSTEM_MODE
			ORDER BY Name
			LIMIT 500
		]) {
			if (recipe.Status__c == ConnectorRunStore.PAUSED_BY_FAILURES) {
				paused.add(recipe.Name);
			} else if (ConnectorRecipeDocument.isId(recipe.Record_Owner_Id__c)) {
				Id owner = Id.valueOf(recipe.Record_Owner_Id__c);
				if (!byOwner.containsKey(owner)) {
					byOwner.put(owner, new List<String>());
				}
				byOwner.get(owner).add(recipe.Name);
			}
		}
		if (!paused.isEmpty()) {
			found.add(
				finding(
					'connector_paused_by_failures',
					BarnHelp.text('Connector', 'Connector_Health_PausedByFailures_Title'),
					BarnHelp.text(
						'Connector',
						'Connector_Health_PausedByFailures_Detail',
						new List<Object>{ String.join(paused, ', ') }
					),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
		List<String> ownerless = new List<String>();
		Set<Id> owners = byOwner.keySet();
		for (User inactive : [SELECT Id FROM User WHERE Id IN :owners AND IsActive = FALSE WITH SYSTEM_MODE]) {
			ownerless.addAll(byOwner.get(inactive.Id));
		}
		if (!ownerless.isEmpty()) {
			found.add(
				finding(
					'connector_owner_inactive',
					BarnHelp.text('Connector', 'Connector_Health_OwnerInactive_Title'),
					BarnHelp.text(
						'Connector',
						'Connector_Health_OwnerInactive_Detail',
						new List<Object>{ String.join(ownerless, ', ') }
					),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
		return found;
	}

	private static HealthCheckService.Finding finding(String key, String title, String detail, String severity) {
		return new HealthCheckService.Finding(key, title, detail, severity, HealthCheckService.CATEGORY_SETTINGS);
	}
}
