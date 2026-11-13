/**
 * The Mirror Case bridge (D-201; ADR-NEXT `NEXT-projects-requests-and-issues.md` decision 7):
 * sends this org's Cases to a service provider running BarnCRM Projects, through the provider's
 * request API, and reads their status back. Off until Send Cases to a service provider is on.
 *
 * Case is never named at compile time: it is resolved through describe and queried by name, so
 * Mirror installs where Case is not available (plan Section 4.2, ADR-0013). What the provider
 * answers is kept on Provider Request (`Provider_Request__c`), keyed by the Case Id, never on Case.
 *
 * Cases go by the Send Cases to a Service Provider flow action (`CaseProviderRequestAction`) or by
 * the nightly step, which sends every open Case of the chosen Type not yet sent and then asks for
 * the status of every request not yet finished. Callouts go to the Named Credential
 * `Barn_Request_Provider`, which the admin creates; nothing secret is stored here. All callouts
 * come before any save, as the platform requires; failures are kept on the Provider Request and
 * in the Error Log, and a failed Case is sent again by the next run.
 */
public with sharing class CaseProviderRequests implements Queueable, Database.AllowsCallouts, Schedulable {
	/** The step's key in the nightly run. */
	public static final String JOB_NAME = 'BarnCRM Mirror: Case requests';
	@TestVisible
	private static final String ENDPOINT = 'callout:Barn_Request_Provider/services/apexrest/barncrm/requests/v1/requests';
	/** Sends in one job, leaving room for the status calls under the callout limit. */
	@TestVisible
	private static final Integer PER_JOB = 50;
	private static final Integer PER_STATUS_CALL = 200;
	private static final String CASE_OBJECT = 'Case';
	private static final String CASE_FIELDS = 'Id, CaseNumber, Subject, Description, Priority, SuppliedName, SuppliedEmail, Contact.Name, Contact.Email';
	private static final Set<String> FINISHED = new Set<String>{
		'Resolved',
		'Closed',
		'Cancelled'
	};
	private static final String CONTEXT = 'CaseProviderRequests';
	@TestVisible
	private static Boolean unavailableForTest = false;

	private final List<Id> toSend;
	private final Boolean readStatus;
	private final List<String> failures = new List<String>();

	/** The nightly run: sweep for unsent Cases, then read status. */
	public CaseProviderRequests() {
		this(null, true);
	}

	@TestVisible
	private CaseProviderRequests(List<Id> toSend, Boolean readStatus) {
		this.toSend = toSend;
		this.readStatus = readStatus;
	}

	/** Sends these Cases now (the flow action), in jobs of 50. */
	public static void send(List<Id> caseIds) {
		if (isOn() && caseIds != null && !caseIds.isEmpty()) {
			System.enqueueJob(new CaseProviderRequests(new List<Id>(new Set<Id>(caseIds)), false));
		}
	}

	/** The nightly step: only while the setting is on and the org has Case. */
	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				BarnHelp.text('Mirror', 'Mirror_CaseRequests_Title'),
				1,
				40,
				new CaseProviderRequests()
			)
			.withSwitch(true)
			.activeWhen(isOn());
	}

	/** Send Cases to a service provider, off at install, and an org with Case. */
	public static Boolean isOn() {
		Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
		return settings != null && settings.Case_Requests_Enabled__c == true && caseType() != null;
	}

	public void execute(SchedulableContext schedule) {
		if (isOn()) {
			System.enqueueJob(new CaseProviderRequests());
		}
	}

	public void execute(QueueableContext job) {
		if (!isOn()) {
			return;
		}
		List<Id> pending = toSend ?? unsent();
		Set<String> sent = accepted(pending);
		List<Id> now = new List<Id>();
		List<Id> later = new List<Id>();
		for (Id caseId : pending) {
			if (!sent.contains(caseId)) {
				(now.size() < PER_JOB ? now : later).add(caseId);
			}
		}
		Map<String, Provider_Request__c> changed = new Map<String, Provider_Request__c>();
		for (Provider_Request__c row : sendAll(now)) {
			changed.put(row.Case_Id__c, row);
		}
		if (readStatus) {
			for (Provider_Request__c row : readAll()) {
				changed.put(row.Case_Id__c, row);
			}
		}
		Database.upsert(
			changed.values(),
			Provider_Request__c.Case_Id__c,
			false,
			AccessLevel.SYSTEM_MODE
		);
		if (!failures.isEmpty()) {
			ErrorLogger.logMessages(failures, CONTEXT, ErrorLogger.SEVERITY_WARNING);
		}
		if (!later.isEmpty() && !Test.isRunningTest()) {
			System.enqueueJob(new CaseProviderRequests(later, false));
		}
	}

	/** Open Cases of the chosen Type, oldest first (1,000 a night). */
	private static List<Id> unsent() {
		List<Id> ids = new List<Id>();
		for (
			SObject row : Database.queryWithBinds(
				'SELECT Id FROM ' +
					CASE_OBJECT +
					' WHERE Type = :caseType AND IsClosed = FALSE ORDER BY CreatedDate LIMIT 1000',
				new Map<String, Object>{ 'caseType' => chosenType() },
				AccessLevel.USER_MODE
			)
		) {
			ids.add(row.Id);
		}
		return ids;
	}

	/** Which of these Cases the provider already accepted (they have a request number). */
	private static Set<String> accepted(List<Id> caseIds) {
		Set<String> keys = new Set<String>();
		for (Id caseId : caseIds) {
			keys.add(caseId);
		}
		Set<String> done = new Set<String>();
		for (Provider_Request__c row : [
			SELECT Case_Id__c
			FROM Provider_Request__c
			WHERE Case_Id__c IN :keys AND Request_Number__c != NULL
			WITH SYSTEM_MODE
		]) {
			done.add(row.Case_Id__c);
		}
		return done;
	}

	/** Posts each Case; answers what to keep for it. */
	private List<Provider_Request__c> sendAll(List<Id> caseIds) {
		List<Provider_Request__c> rows = new List<Provider_Request__c>();
		if (caseIds.isEmpty()) {
			return rows;
		}
		for (
			SObject record : Database.queryWithBinds(
				'SELECT ' + CASE_FIELDS + ' FROM ' + CASE_OBJECT + ' WHERE Id IN :caseIds',
				new Map<String, Object>{ 'caseIds' => caseIds },
				AccessLevel.USER_MODE
			)
		) {
			String caseNumber = (String) record.get('CaseNumber');
			SObject contact = record.getSObject('Contact');
			Map<String, Object> body = new Map<String, Object>{
				'orgId' => UserInfo.getOrganizationId(),
				'reference' => caseNumber,
				'subject' => String.isBlank((String) record.get('Subject'))
					? caseNumber
					: record.get('Subject'),
				'description' => record.get('Description'),
				'priority' => record.get('Priority'),
				'requesterName' => contact?.get('Name') ?? record.get('SuppliedName'),
				'requesterEmail' => contact?.get('Email') ?? record.get('SuppliedEmail')
			};
			Provider_Request__c row = new Provider_Request__c(
				Name = caseNumber,
				Case_Id__c = record.Id,
				Synced__c = Datetime.now()
			);
			HttpResponse answer = call('POST', ENDPOINT, JSON.serialize(body), caseNumber);
			if (
				answer != null && (answer.getStatusCode() == 200 || answer.getStatusCode() == 201)
			) {
				keep(row, (Map<String, Object>) JSON.deserializeUntyped(answer.getBody()));
				row.Error__c = null;
			} else {
				row.Error__c = refusal(answer);
			}
			rows.add(row);
		}
		return rows;
	}

	/** Asks for the status of every sent request not yet finished, 200 a call. */
	private List<Provider_Request__c> readAll() {
		List<Provider_Request__c> rows = new List<Provider_Request__c>();
		Map<String, Provider_Request__c> byNumber = new Map<String, Provider_Request__c>();
		for (Provider_Request__c row : [
			SELECT Id, Name, Case_Id__c
			FROM Provider_Request__c
			WHERE Request_Number__c != NULL AND Status__c NOT IN :FINISHED
			WITH SYSTEM_MODE
			ORDER BY Synced__c ASC NULLS FIRST
			LIMIT 2000
		]) {
			byNumber.put(row.Name, row);
		}
		List<String> batch = new List<String>();
		for (String caseNumber : byNumber.keySet()) {
			batch.add(caseNumber);
			if (batch.size() == PER_STATUS_CALL) {
				rows.addAll(read(batch, byNumber));
				batch = new List<String>();
			}
		}
		if (!batch.isEmpty()) {
			rows.addAll(read(batch, byNumber));
		}
		return rows;
	}

	private List<Provider_Request__c> read(
		List<String> refs,
		Map<String, Provider_Request__c> byNumber
	) {
		List<Provider_Request__c> rows = new List<Provider_Request__c>();
		String query =
			'?orgId=' +
			EncodingUtil.urlEncode(UserInfo.getOrganizationId(), 'UTF-8') +
			'&refs=' +
			EncodingUtil.urlEncode(String.join(refs, ','), 'UTF-8');
		HttpResponse answer = call(
			'GET',
			ENDPOINT + query,
			null,
			BarnHelp.text('Mirror', 'Mirror_CaseRequests_StatusCall')
		);
		if (answer == null || answer.getStatusCode() != 200) {
			return rows;
		}
		Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(answer.getBody());
		for (Object item : (List<Object>) body.get('requests')) {
			Map<String, Object> request = (Map<String, Object>) item;
			Provider_Request__c known = byNumber.get((String) request.get('reference'));
			if (known != null) {
				Provider_Request__c row = new Provider_Request__c(
					Case_Id__c = known.Case_Id__c,
					Synced__c = Datetime.now()
				);
				rows.add(keep(row, request));
			}
		}
		return rows;
	}

	/** The provider's number, status and resolution onto the row. */
	private static Provider_Request__c keep(Provider_Request__c row, Map<String, Object> answer) {
		row.Request_Number__c = text(answer.get('number'), 30);
		row.Status__c = text(answer.get('status'), 40);
		row.Resolution__c = text(answer.get('resolution'), 32768);
		return row;
	}

	private static String text(Object value, Integer max) {
		return value == null ? null : String.valueOf(value).abbreviate(max);
	}

	/** One callout; null when it could not be made, with the reason kept for the Error Log. */
	private HttpResponse call(String method, String endpoint, String body, String what) {
		HttpRequest request = new HttpRequest();
		request.setMethod(method);
		request.setEndpoint(endpoint);
		request.setHeader('Content-Type', 'application/json');
		request.setTimeout(20000);
		if (body != null) {
			request.setBody(body);
		}
		try {
			HttpResponse answer = new Http().send(request);
			if (answer.getStatusCode() >= 300) {
				failures.add(
					BarnHelp.text(
						'Mirror',
						'Mirror_CaseRequests_Refused',
						new List<Object>{ what, answer.getStatusCode() }
					)
				);
			}
			return answer;
		} catch (Exception failed) {
			failures.add(
				BarnHelp.text(
					'Mirror',
					'Mirror_CaseRequests_NotReached',
					new List<Object>{ what, failed.getMessage() }
				)
			);
			return null;
		}
	}

	/** The short reason a send failed, kept on the Provider Request. */
	private static String refusal(HttpResponse answer) {
		if (answer == null) {
			return BarnHelp.text('Mirror', 'Mirror_CaseRequests_ErrorNotReached');
		}
		return BarnHelp.text(
				'Mirror',
				'Mirror_CaseRequests_ErrorRefused',
				new List<Object>{ answer.getStatusCode() }
			)
			.abbreviate(255);
	}

	/** The Case Type the nightly run sends, default Service Provider. */
	private static String chosenType() {
		Mirror_Settings__c settings = Mirror_Settings__c.getOrgDefaults();
		return String.isBlank(settings?.Case_Requests_Type__c)
			? 'Service Provider'
			: settings.Case_Requests_Type__c;
	}

	@TestVisible
	private static Schema.SObjectType caseType() {
		return unavailableForTest ? null : NamespaceUtil.globalDescribe().get(CASE_OBJECT);
	}
}
