/**
 * Starts BarnCRM Connector's runner chain when a run is queued (canonical model R-CR4). The
 * trigger keeps Salesforce's default running user, the Automated Process user, so the runner
 * and every run it takes run as that identity, never as the person who pressed Run Now or whose
 * flow queued the run (D-215).
 *
 * Not routed through `TriggerDispatcher`: there is no record to act on, and starting the runner
 * is safe to ask for twice, so one call covers however many events arrive together.
 */
trigger ConnectorStartTrigger on Connector_Start__e(after insert) {
	ConnectorRunner.start();
}
