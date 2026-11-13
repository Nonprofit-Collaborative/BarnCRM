/**
 * The Send Cases to a Service Provider flow action (D-201; ADR-0221
 * `0221-projects-requests-and-issues.md` decision 7): a record-triggered flow on Case sends a
 * Case at once instead of waiting for the nightly run. The work is `CaseProviderRequests`.
 *
 * `global` because a Flow in a subscriber org calls it (ADR-0017, ADR-0051). It takes Case Ids,
 * never a Case, so Mirror names no standard object at compile time (ADR-0013).
 */
global with sharing class CaseProviderRequestAction {
	@InvocableMethod(
		label='Send Cases to a Service Provider'
		description='Sends these Cases to the service provider set up in the Barn_Request_Provider named credential, in the background. Does nothing while Send Cases to a service provider is off. A Case already accepted by the provider is not sent again.'
		category='BarnCRM'
	)
	global static void send(List<Id> caseIds) {
		CaseProviderRequests.send(caseIds);
	}
}
