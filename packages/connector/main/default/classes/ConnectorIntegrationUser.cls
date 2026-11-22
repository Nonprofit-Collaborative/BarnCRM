/**
 * The integration user (canonical model R-CR4, R-CS1; design Section 3.10; security review F12):
 * the one user Integration User recipes run as. Salesforce sets a platform event trigger's running
 * user only through `PlatformEventSubscriberConfig`, which Setup shows but cannot edit, so choosing
 * the user here saves it as run state and queues a job, as the admin, that writes that
 * configuration for `ConnectorStartUserTrigger` through the org connection (ADR-0148), then gives
 * the user BarnCRM Connections and takes it from the previous one. The admin then suspends and
 * resumes the subscription in Setup so it takes effect at once.
 *
 * The user's Id is the one Id a browser sends here: it is used only after the checks below (an
 * active user of type Standard without Modify All Data, View All Data or the System Administrator
 * profile, chosen by a Connector admin holding BarnCRM Connector Admin and Manage Named
 * Credentials or Customize Application), and BarnCRM Connections goes to no one else (F12).
 */
public with sharing class ConnectorIntegrationUser {
	/** Run state: the chosen user's Id (`Connector.Integration_User_Id__c`), written at once. */
	public static final String KEY_USER = SettingsState.moduleKey(
		ConnectorClock.STATE_PREFIX,
		'Integration_User_Id__c'
	);
	public static final String SUBSCRIBER = 'BarnCRM_Connector_Start_User';
	public static final String LANE_TRIGGER = 'ConnectorStartUserTrigger';
	public static final String ORG_CONNECTION = 'Barn_Org_Connection';
	private static final String TOOLING = '/services/data/v67.0/tooling/';
	private static final Integer TIMEOUT_MS = 20000;

	/** The Integration User card as the page shows it. */
	public class View {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String username;
		@AuraEnabled
		public Boolean active = false;
		@AuraEnabled
		public Boolean hasConnections = false;
		/** Whether the org connection the subscriber write needs is set up (ADR-0148). */
		@AuraEnabled
		public Boolean orgConnectionReady = false;
		/** The latest subscriber write's job status (Queued, Processing, Completed, Failed). */
		@AuraEnabled
		public String lastWrite;
		/** True once a runner or clock job ran as this user in the last 7 days. */
		@AuraEnabled
		public Boolean confirmed = false;
	}

	/** The chosen user's Id, or null. */
	public static Id chosenId() {
		String stored = SettingsState.text(KEY_USER);
		return ConnectorRecipeDocument.isId(stored) ? Id.valueOf(stored) : null;
	}

	/** Whether a user is chosen and active. */
	public static Boolean ready() {
		Id chosen = chosenId();
		return chosen != null && [SELECT COUNT() FROM User WHERE Id = :chosen AND IsActive = TRUE WITH SYSTEM_MODE] > 0;
	}

	/** The recipe identities, for the Record Change loop guard (R-CR6). */
	public static Set<Id> identityIds() {
		Set<Id> found = new Set<Id>();
		for (Id each : new List<Id>{ ConnectorIdentity.automatedProcessId(), chosenId() }) {
			if (each != null) {
				found.add(each);
			}
		}
		return found;
	}

	public static View view() {
		return view(chosenId());
	}

	private static View view(Id chosen) {
		View result = new View();
		result.orgConnectionReady =
			[SELECT COUNT() FROM NamedCredential WHERE DeveloperName = :ORG_CONNECTION WITH SYSTEM_MODE] > 0;
		for (AsyncApexJob job : [
			SELECT Status
			FROM AsyncApexJob
			WHERE ApexClass.Name = 'ConnectorIntegrationUser'
			WITH SYSTEM_MODE
			ORDER BY CreatedDate DESC
			LIMIT 1
		]) {
			result.lastWrite = job.Status;
		}
		if (chosen == null) {
			return result;
		}
		for (User row : [SELECT Id, Name, Username, IsActive FROM User WHERE Id = :chosen WITH SYSTEM_MODE]) {
			result.id = row.Id;
			result.name = row.Name;
			result.username = row.Username;
			result.active = row.IsActive;
		}
		result.hasConnections = ConnectorConnections.holds(chosen, ConnectorConnections.ACCESS_SET, null);
		Datetime since = Datetime.now().addDays(-7);
		result.confirmed =
			[
				SELECT COUNT()
				FROM AsyncApexJob
				WHERE
					CreatedById = :chosen
					AND ApexClass.Name IN ('ConnectorClock', 'ConnectorRunner')
					AND CreatedDate >= :since
				WITH SYSTEM_MODE
			] > 0;
		return result;
	}

	/**
	 * Chooses the integration user, or none when `userId` is blank (R-CS1). Saved org-wide; the
	 * subscriber write and the BarnCRM Connections assignment follow in a job.
	 */
	public static View choose(String userId) {
		ConnectorConnections.requireWriter();
		if (!ConnectorConnections.holdsAdminSet()) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Error_NoManage'));
		}
		Id chosen = null;
		if (String.isNotBlank(userId)) {
			String trimmed = userId.trim();
			if (
				!ConnectorRecipeDocument.isId(trimmed) ||
				[
					SELECT COUNT()
					FROM User
					WHERE Id = :trimmed AND IsActive = TRUE AND UserType = 'Standard'
					WITH SYSTEM_MODE
				] == 0
			) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_IntegrationUser_ErrorChoice')
				);
			}
			chosen = Id.valueOf(trimmed);
			if (seesEverything(chosen)) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_IntegrationUser_ErrorTooMuch')
				);
			}
		}
		Id previous = chosenId();
		SettingsState.put(new Map<String, Object>{ KEY_USER => chosen == null ? null : String.valueOf(chosen) });
		try {
			AsyncStarter.queue(new SubscriberJob(chosen, previous), 'ConnectorIntegrationUser.choose');
		} catch (Exception busy) {
			throw new ConnectorConnections.ConnectorException(busy.getMessage());
		}
		return view(chosen);
	}

	/**
	 * Whether a user reaches every record: Modify All Data or View All Data from the profile or
	 * any permission set. The profile's own permission set is one of the user's assignments, so
	 * this also covers the System Administrator profile, by what it grants rather than by its
	 * name (which an org can clone or a translation can change). Integration User recipes run
	 * with this user's access, so such a user would give them all of it (F12).
	 */
	@TestVisible
	private static Boolean seesEverything(Id userId) {
		return [
				SELECT COUNT()
				FROM PermissionSetAssignment
				WHERE
					AssigneeId = :userId
					AND (PermissionSet.PermissionsModifyAllData = TRUE
					OR PermissionSet.PermissionsViewAllData = TRUE)
				WITH SYSTEM_MODE
			] > 0;
	}

	/**
	 * Writes the subscriber configuration (callouts first: none may follow a write), then moves
	 * BarnCRM Connections from the previous user to the chosen one. Runs as the admin who chose,
	 * whose session the org connection sends (ADR-0148).
	 */
	public with sharing class SubscriberJob implements Queueable, Database.AllowsCallouts {
		private Id chosen;
		private Id previous;

		public SubscriberJob(Id chosen, Id previous) {
			this.chosen = chosen;
			this.previous = previous;
		}

		public void execute(QueueableContext context) {
			try {
				writeSubscriber(chosen);
			} catch (Exception refused) {
				// The lane cannot start, so access stays as it was; Save again once fixed. An Error
				// Log write and a permission set assignment cannot share a transaction.
				ErrorLogger.logMessage(
					BarnHelp.text(
						'Connector',
						'Connector_Log_SubscriberFailed',
						new List<Object>{ refused.getMessage() }
					),
					'ConnectorIntegrationUser',
					ErrorLogger.SEVERITY_ERROR
				);
				return;
			}
			moveConnections(chosen, previous);
		}
	}

	/** Creates, updates or (no user) deletes `BarnCRM_Connector_Start_User` through the Tooling API. */
	@TestVisible
	private static void writeSubscriber(Id chosen) {
		String namespace = String.isBlank(NamespaceUtil.namespacePrefix()) ? null : NamespaceUtil.namespacePrefix();
		List<ApexTrigger> consumer = [
			SELECT Id
			FROM ApexTrigger
			WHERE Name = :LANE_TRIGGER AND NamespacePrefix = :namespace
			WITH SYSTEM_MODE
			LIMIT 1
		];
		Map<String, Object> found = (Map<String, Object>) JSON.deserializeUntyped(
			send(
				'GET',
				'query/?q=' +
				EncodingUtil.urlEncode(
					'SELECT Id FROM PlatformEventSubscriberConfig WHERE DeveloperName = \'' + SUBSCRIBER + '\'',
					'UTF-8'
				),
				null
			)
		);
		List<Object> rows = (List<Object>) found.get('records');
		String existing = rows == null || rows.isEmpty() ? null : (String) ((Map<String, Object>) rows[0]).get('Id');
		if (chosen == null) {
			if (existing != null) {
				send('DELETE', 'sobjects/PlatformEventSubscriberConfig/' + existing, null);
			}
			return;
		}
		if (consumer.isEmpty()) {
			throw new ConnectorConnections.ConnectorException(LANE_TRIGGER);
		}
		Map<String, Object> body = new Map<String, Object>{
			'UserId' => chosen,
			'PlatformEventConsumerId' => consumer[0].Id,
			'BatchSize' => 200
		};
		if (existing == null) {
			body.put('DeveloperName', SUBSCRIBER);
			body.put('MasterLabel', 'BarnCRM Connector Start User');
			send('POST', 'sobjects/PlatformEventSubscriberConfig/', JSON.serialize(body));
		} else {
			send('PATCH', 'sobjects/PlatformEventSubscriberConfig/' + existing, JSON.serialize(body));
		}
	}

	/** BarnCRM Connections to the chosen user, and off the previous one unless a Connector admin. */
	private static void moveConnections(Id chosen, Id previous) {
		Id connections = ConnectorConnections.ensureAccessSet();
		if (chosen != null && !ConnectorConnections.holds(chosen, ConnectorConnections.ACCESS_SET, null)) {
			Database.insert(
				new PermissionSetAssignment(AssigneeId = chosen, PermissionSetId = connections),
				AccessLevel.SYSTEM_MODE
			);
		}
		if (
			previous != null &&
			previous != chosen &&
			!ConnectorConnections.holds(previous, ConnectorConnections.ADMIN_SET, NamespaceUtil.namespacePrefix())
		) {
			Database.delete(
				[
					SELECT Id
					FROM PermissionSetAssignment
					WHERE AssigneeId = :previous AND PermissionSetId = :connections
					WITH SYSTEM_MODE
				],
				AccessLevel.SYSTEM_MODE
			);
		}
	}

	// The call goes through the org connection Barn_Org_Connection, which adds no authorization
	// header (ADR-0148), so the job's own session is sent, as Core's OrgToolingApi sends it. No
	// stored secret is involved and nothing of the request is kept.
	@SuppressWarnings('PMD.ApexSuggestUsingNamedCred')
	private static String send(String method, String path, String body) {
		HttpRequest call = new HttpRequest();
		call.setEndpoint('callout:' + ORG_CONNECTION + TOOLING + path);
		call.setMethod(method);
		call.setTimeout(TIMEOUT_MS);
		call.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
		call.setHeader('Content-Type', 'application/json');
		if (body != null) {
			call.setBody(body);
		}
		HttpResponse response = new Http().send(call);
		Integer status = response.getStatusCode();
		if (status >= 200 && status < 300) {
			return response.getBody();
		}
		throw new ConnectorConnections.ConnectorException(status + ' ' + String.valueOf(response.getBody()).left(500));
	}
}
