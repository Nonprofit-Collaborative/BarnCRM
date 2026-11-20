/**
 * Starts the Integration User lane of BarnCRM Connector (canonical model R-CR4, R-CR6). Its running
 * user is the chosen integration user, set through the `PlatformEventSubscriberConfig` BarnCRM
 * writes when an admin chooses one; the runner and heartbeat it starts keep that identity.
 * Running as anyone else (the config was never written, or not yet applied), it does nothing and
 * the runs wait, which Health Check reports.
 *
 * Not routed through `TriggerDispatcher`: there is no record to act on.
 */
trigger ConnectorStartUserTrigger on Connector_Start_User__e(after insert) {
	ConnectorClock.onStart(ConnectorClock.LANE_USER);
}
