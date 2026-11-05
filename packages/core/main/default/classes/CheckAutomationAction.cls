/**
 * The Check BarnCRM Automation action: whether an organization's own flow should run now,
 * answering the same questions BarnCRM's trigger dispatcher asks (ADR-0165 dispatcher errors and
 * Automation Control). A flow calls it first and ends when Run is false.
 *
 * It answers false when the BarnCRM Automation Control setting that applies to the person saving
 * has Pause All or Bypass on, when the timed pause on the Automation page is in effect, or when
 * the flow is listed on the Automation page under the given name and its switch is off. A name
 * that is not listed is not switched off, so a flow that never asked to be listed still follows
 * the pause and the setting.
 *
 * `global` because only a global invocable method is offered to a Flow in a subscriber org;
 * every variable is permanent once the package is managed. Reads no record: the setting costs no
 * query, the pause and the switches are read once per transaction.
 */
global with sharing class CheckAutomationAction {
	/** Why an automation does not run, or `Run`. */
	@TestVisible
	private static final String REASON_RUN = 'Run';
	@TestVisible
	private static final String REASON_SETTING = 'Automation Control';
	@TestVisible
	private static final String REASON_PAUSED = 'Paused';
	@TestVisible
	private static final String REASON_SWITCHED_OFF = 'Switched Off';

	/** One question. */
	global class Request {
		@InvocableVariable(
			label='Automation Name'
			description='Optional. The name your flow is listed under on the Automation page of BarnCRM Settings (Flow: and the flow API name, for example Flow:My_Gift_Flow). Leave it blank to follow only the pause and the BarnCRM Automation Control setting.'
		)
		global String automationName;
	}

	/** The answer, in the same position as the question. */
	global class Result {
		@InvocableVariable(
			label='Run'
			description='True when the flow should do its work now; false when automation is paused, bypassed for the person saving, or this flow is switched off.'
		)
		global Boolean run;

		@InvocableVariable(
			label='Reason'
			description='Run, Automation Control (Pause All or Bypass applies to the person saving), Paused (the timed pause) or Switched Off.'
		)
		global String reason;
	}

	@InvocableMethod(
		label='Check BarnCRM Automation'
		description='Whether your own flow should run now: false while BarnCRM automation is paused, bypassed for the person saving by the BarnCRM Automation Control setting, or this flow is switched off on the Automation page.'
		category='BarnCRM'
	)
	global static List<Result> check(List<Request> requests) {
		List<Result> results = new List<Result>();
		if (requests == null) {
			return results;
		}
		Boolean offForUser = AutomationControl.isOffForRunningUser();
		Boolean paused = !offForUser && AutomationControl.isPaused();
		for (Request request : requests) {
			Result answer = new Result();
			if (offForUser) {
				answer.reason = REASON_SETTING;
			} else if (paused) {
				answer.reason = REASON_PAUSED;
			} else if (
				request != null &&
				String.isNotBlank(request.automationName) &&
				!AutomationControl.isEnabled(request.automationName.trim())
			) {
				answer.reason = REASON_SWITCHED_OFF;
			} else {
				answer.reason = REASON_RUN;
			}
			answer.run = answer.reason == REASON_RUN;
			results.add(answer);
		}
		return results;
	}
}
