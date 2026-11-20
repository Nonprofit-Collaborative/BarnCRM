/**
 * Starts BarnCRM Connector's BarnCRM Automation and System lane (canonical model R-CR4, R-CR6).
 * The trigger keeps Salesforce's default running user, the Automated Process user, so the runner,
 * the recipe clock and every run they take run as that identity, never as the person who pressed
 * Run Now or whose flow queued the run (D-215).
 *
 * Not routed through `TriggerDispatcher`: there is no record to act on, and starting the runner
 * and the clock is safe to ask for twice, so one call covers however many events arrive together.
 */
trigger ConnectorStartTrigger on Connector_Start__e(after insert) {
	ConnectorClock.onStart(ConnectorClock.LANE_AUTOMATION);
}
