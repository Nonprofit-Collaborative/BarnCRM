/**
 * What the recipe tests share (CN-02, CN-06): saved maps, recipes, one ready connection in a
 * faked credential store, and an app that answers and keeps every request it was sent.
 */
@IsTest
public class ConnectorRecipeTestData {
	public static final String CONNECTION = 'BarnConn_rest_test1';

	/** A record map onto Contact: last name and email, matched by email. */
	public static Id contactMap(String name) {
		return saveMap(
			name,
			'Contact',
			'{"version":1,"from":{"kind":"json"},"to":{"kind":"record","object":"Contact"},' +
				'"columns":[{"source":"last","target":"LastName","required":true},{"source":"mail","target":"Email"}],' +
				'"match":{"by":"field","field":"Email","several":"newest","none":"create"}}'
		);
	}

	/** A JSON body map: the found contact's last name as `name`. */
	public static Id bodyMap(String name) {
		return saveMap(
			name,
			null,
			'{"version":1,"from":{"kind":"json"},"to":{"kind":"json"},"columns":[{"source":"last","target":"name"}]}'
		);
	}

	public static Id saveMap(String name, String objectName, String document) {
		Saved_Transform__c row = new Saved_Transform__c(
			Name = name,
			Kind__c = ConnectorMapRuntime.KIND_MAP,
			Object_Name__c = objectName,
			Definition_JSON__c = document
		);
		insert as system row;
		return row.Id;
	}

	/** A recipe saved as it is; Active ones have the same definition and draft. */
	public static Connector_Recipe__c recipe(String name, String document, Boolean active, String runAs) {
		Connector_Recipe__c row = new Connector_Recipe__c(
			Name = name,
			Status__c = active ? ConnectorRunStore.ACTIVE : ConnectorRecipes.DRAFT,
			Trigger_Kind__c = ConnectorRecipes.MANUAL,
			Run_As__c = runAs,
			Version__c = active ? 1 : 0,
			Draft_JSON__c = document,
			Definition_JSON__c = active ? document : null
		);
		insert as system row;
		return row;
	}

	/** A document of steps under a manual trigger. */
	public static String document(String stepsJson) {
		return '{"version":1,"trigger":{"kind":"manual"},"steps":' + stepsJson + '}';
	}

	/** A queued run of a recipe, as the runner reads it back. */
	public static Connector_Run__c queuedRun(Connector_Recipe__c recipe, String inputJson, Boolean isTest) {
		Connector_Run__c run = new Connector_Run__c(
			Recipe__c = recipe.Id,
			Started_By__c = isTest ? 'Test' : 'Manual',
			Ran_As__c = recipe.Run_As__c,
			Recipe_Version__c = recipe.Version__c,
			Input_JSON__c = inputJson,
			Is_Test__c = isTest
		);
		ConnectorRunStore.queue(new List<Connector_Run__c>{ run });
		for (Connector_Run__c queued : ConnectorRunStore.queued(50, ConnectorRunStore.ALL_RUN_AS, false)) {
			if (queued.Id == run.Id) {
				return queued;
			}
		}
		return null;
	}

	/** Runs every queued run the way the runner's job does, in this transaction. */
	public static Connector_Run__c runAll(Id runId) {
		ConnectorRunner.process(
			ConnectorRunStore.queued(50, ConnectorRunStore.ALL_RUN_AS, false),
			new ConnectorRunner.Guard()
		);
		return [
			SELECT
				Id,
				Status__c,
				Failed_Step__c,
				Error_Message__c,
				Records_Written__c,
				State_JSON__c,
				Step_Log_JSON__c,
				Finished_At__c
			FROM Connector_Run__c
			WHERE Id = :runId
			WITH SYSTEM_MODE
		];
	}

	/** One ready connection (a key, callouts on) in a faked credential store. */
	public static void readyConnection() {
		ConnectorConnections.org = new FakeOrg();
	}

	/** A faked credential store with no connection, so no test reads the org's own. */
	public static void noConnections() {
		FakeOrg empty = new FakeOrg();
		empty.labels = new Map<String, String>();
		ConnectorConnections.org = empty;
	}

	public class FakeOrg extends ConnectorOrg {
		public Map<String, String> labels = new Map<String, String>{ CONNECTION => 'Test App' };

		public FakeOrg() {
			fake = true;
		}

		public override Map<String, String> labelsByName() {
			return labels;
		}

		public override ConnectorOrg.Pair read(String name, String label) {
			ConnectorOrg.Pair pair = new ConnectorOrg.Pair();
			pair.name = name;
			pair.label = label;
			pair.principal = ConnectorConnections.BEARER;
			pair.url = 'https://api.example.com';
			pair.linked = true;
			pair.calloutsEnabled = true;
			pair.keyStored = true;
			return pair;
		}

		public override Set<Id> grantedEntities(Id permissionSetId) {
			return new Set<Id>();
		}
	}

	/** An app that answers each request with one status and body, and keeps the requests. */
	public class App implements HttpCalloutMock {
		public Integer status = 200;
		public String body = '{"ok":true}';
		public List<HttpRequest> requests = new List<HttpRequest>();

		public App(Integer status, String body) {
			this.status = status;
			this.body = body;
		}

		public HttpResponse respond(HttpRequest request) {
			requests.add(request);
			HttpResponse response = new HttpResponse();
			response.setStatusCode(status);
			response.setBody(body);
			return response;
		}
	}
}
