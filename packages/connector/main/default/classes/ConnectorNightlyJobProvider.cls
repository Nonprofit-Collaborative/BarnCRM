/**
 * The class Core finds by name (registered in the Connector catalog row) to add BarnCRM
 * Connector's step to the one nightly run (ADR-0166; canonical model R-RUN2, R-CR6). The step
 * deletes finished runs older than their recipe's Keep Runs Days and publishes the start event of
 * each lane with recipe work, which starts its heartbeat if it stopped. Its switch ships on; it
 * runs only while the module is on.
 *
 * The nightly run is a staff member's job, so the step starts no recipe work itself: the start
 * events' triggers run as the recipe identities (R-CR4).
 */
@NamespaceAccessible
public with sharing class ConnectorNightlyJobProvider implements NightlyStepProvider {
	public static final String STEP_KEY = 'Connector';

	@NamespaceAccessible
	public ConnectorNightlyJobProvider() {
		return;
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{
			new NightlyStep(STEP_KEY, BarnHelp.text('Connector', 'Connector_NightlyStep'), 2, 40, new Cleanup())
				.withSwitch(true)
				.activeWhen(!ModuleManagerService.turnedOff().contains(ConnectorConnections.MODULE.toLowerCase()))
		};
	}

	/** The step's work: the run cleanup, then the heartbeat check. */
	public with sharing class Cleanup implements Schedulable {
		public void execute(SchedulableContext context) {
			ConnectorRunStore.deleteExpired();
			ConnectorClock.publish(ConnectorClock.lanesNeeded());
		}
	}
}
