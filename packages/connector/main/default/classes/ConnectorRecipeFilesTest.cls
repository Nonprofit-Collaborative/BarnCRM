/**
 * Dana, the Connector admin, publishes versions, rolls back, discards draft changes, exports a
 * recipe and imports it or a template (CN-08; canonical model R-CR11 to R-CR13; D-216; security
 * review F1, F4). Import stores nothing, matches maps and connections by name, leaves what it
 * cannot match blank and listed, and refuses any file carrying a merge field, a secret, a
 * formula option or an unsafe address; Sam, a viewer, cannot import.
 */
@IsTest(testFor='ApexClass:ConnectorRecipeFiles, ApexClass:ConnectorRecipes, ApexClass:ConnectorRecipesController')
private class ConnectorRecipeFilesTest {
	private static final String VIEWER_SET = 'BarnCRM_Connector_Viewer';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static User admin() {
		return TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static String pingDocument(String path) {
		return ConnectorRecipeTestData.document(
			'[{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"GET","path":"' +
				path +
				'"}]'
		);
	}

	private static Connector_Recipe__c stored(Id recipeId) {
		return [
			SELECT Definition_JSON__c, Draft_JSON__c, Previous_JSON__c, Version__c
			FROM Connector_Recipe__c
			WHERE Id = :recipeId
			WITH SYSTEM_MODE
		];
	}

	/** A template: a Basic sign-in on a host locked to a data center, one action and one recipe. */
	private static Map<String, Object> template() {
		return new Map<String, Object>{
			'key' => 'mailchimp',
			'label' => 'Mailchimp',
			'version' => 1,
			'auth' => new Map<String, Object>{
				'kind' => ConnectorConnections.BASIC,
				'params' => new List<Object>{ new Map<String, Object>{ 'name' => 'Password', 'label' => 'API key' } }
			},
			'baseUrl' => 'https://{dc}.api.mailchimp.com/3.0',
			'urlParams' => new List<Object>{
				new Map<String, Object>{
					'name' => 'dc',
					'label' => 'Data center',
					'pattern' => '^[a-z]{2}[0-9]{1,3}$',
					'fromParam' => 'Password',
					'after' => '-'
				}
			},
			'check' => new Map<String, Object>{ 'method' => 'GET', 'path' => '/ping' },
			'actions' => new List<Object>{
				new Map<String, Object>{
					'key' => 'upsertMembers',
					'label' => 'Add or update subscribers',
					'method' => 'POST',
					'path' => '/lists/{listId}'
				}
			},
			'recipes' => new List<Object>{
				new Map<String, Object>{
					'name' => 'Add New People',
					'draft' => new Map<String, Object>{
						'version' => 1,
						'trigger' => new Map<String, Object>{ 'kind' => 'manual' },
						'steps' => new List<Object>{
							new Map<String, Object>{ 'id' => 'send', 'kind' => 'callApp', 'action' => 'upsertMembers' }
						}
					}
				}
			}
		};
	}

	private static String refusal(String fileText) {
		try {
			ConnectorRecipesController.importFile(fileText);
		} catch (AuraHandledException refused) {
			return refused.getMessage();
		}
		return null;
	}

	private static String expected(String key, Object detail) {
		return BarnHelp.text('Connector', key, new List<Object>{ detail });
	}

	@IsTest
	static void publishKeepsThePreviousVersionForRollBackAndDiscard() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.readyConnection();

			Test.startTest();
			ConnectorRecipes.Recipe first = ConnectorRecipesController.saveDraft(
				null,
				'Ping',
				null,
				pingDocument('/one'),
				null
			);
			first = ConnectorRecipesController.publish(first.id);
			ConnectorRecipesController.saveDraft(first.id, 'Ping', null, pingDocument('/two'), null);
			ConnectorRecipes.Recipe second = ConnectorRecipesController.publish(first.id);
			ConnectorRecipesController.saveDraft(first.id, 'Ping', null, pingDocument('/three'), null);
			ConnectorRecipes.Recipe rolled = ConnectorRecipesController.rollBack(first.id);
			Connector_Recipe__c afterRollBack = stored(first.id);
			ConnectorRecipes.Recipe discarded = ConnectorRecipesController.discardDraft(first.id);
			Test.stopTest();

			Assert.isFalse(first.canRollBack, 'Nothing before the first Publish.');
			Assert.isTrue(second.canRollBack);
			Assert.areEqual(3, rolled.version, 'Roll Back publishes, so the version goes up.');
			Assert.isTrue(afterRollBack.Definition_JSON__c.contains('/one'));
			Assert.isTrue(afterRollBack.Previous_JSON__c.contains('/two'), 'Roll Back again returns to it.');
			Assert.isTrue(afterRollBack.Draft_JSON__c.contains('/three'), 'The draft is left alone.');
			Assert.isFalse(discarded.unpublished, 'The draft is the published version again.');
			Assert.isTrue(stored(first.id).Draft_JSON__c.contains('/one'));
		}
	}

	@IsTest
	static void rollBackAndDiscardNeedSomethingToGoBackTo() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.readyConnection();
			ConnectorRecipes.Recipe draft = ConnectorRecipesController.saveDraft(
				null,
				'Never Published',
				null,
				pingDocument('/one'),
				null
			);

			Test.startTest();
			String noPrevious;
			String noPublished;
			try {
				ConnectorRecipesController.rollBack(draft.id);
			} catch (AuraHandledException refused) {
				noPrevious = refused.getMessage();
			}
			try {
				ConnectorRecipesController.discardDraft(draft.id);
			} catch (AuraHandledException refused) {
				noPublished = refused.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Recipe_ErrorNoPrevious'), noPrevious);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Recipe_ErrorNotPublished'), noPublished);
		}
	}

	@IsTest
	static void exportCarriesNamesNotSecretsAndImportsBackAsAnUnsavedDraft() {
		System.runAs(admin()) {
			ConnectorRecipeTestData.readyConnection();
			Id bodyId = ConnectorRecipeTestData.bodyMap('Contact Body');
			String document =
				'{"version":1,"trigger":{"kind":"manual","sample":{"last":"Lovelace"}},"steps":[' +
				'{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"POST","path":"/people","bodyMap":"' +
				bodyId +
				'","headers":[{"name":"X-Api-Key","value":"typed1234567890"},{"name":"Accept","value":"application/json"}]}]}';
			ConnectorRecipes.Recipe saved = ConnectorRecipesController.saveDraft(
				null,
				'Send People',
				'Sends',
				document,
				null
			);

			Test.startTest();
			String fileText = ConnectorRecipesController.exportRecipe(saved.id);
			ConnectorRecipeFiles.Imported matched = ConnectorRecipesController.importFile(fileText);
			delete as system new Saved_Transform__c(Id = bodyId);
			ConnectorRecipeFiles.Imported unmatched = ConnectorRecipesController.importFile(fileText);
			Test.stopTest();

			Assert.isFalse(fileText.contains('typed1234567890'), 'A sign-in header value never leaves the org.');
			Assert.isFalse(fileText.contains('Lovelace'), 'Sample data is not exported.');
			Map<String, Object> file = (Map<String, Object>) JSON.deserializeUntyped(fileText);
			Map<String, Object> names = (Map<String, Object>) file.get('names');
			Assert.areEqual('Contact Body', names.get(String.valueOf(bodyId)));
			Assert.areEqual('Test App', names.get(ConnectorRecipeTestData.CONNECTION));

			Assert.areEqual(ConnectorRecipeFiles.RECIPE, matched.kind);
			Assert.areEqual('Send People', matched.recipes[0].name);
			Map<String, Object> step = (Map<String, Object>) ((List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(
					matched.recipes[0].draftJson
				))
				.get('steps'))[0];
			Assert.areEqual(String.valueOf(bodyId), step.get('bodyMap'), 'Matched by name.');
			Assert.areEqual(ConnectorRecipeTestData.CONNECTION, step.get('connection'), 'Matched by label.');
			Assert.areEqual(new List<Object>{ 'headers' }, step.get('fill'), 'The blanked header is highlighted.');
			Assert.areEqual(new List<String>{ 'send' }, matched.recipes[0].blanks);

			Assert.isTrue(unmatched.recipes[0].draftJson.contains('"bodyMap":""'), 'No match is left blank.');
			Assert.isTrue(unmatched.recipes[0].draftJson.contains('"bodyMap"]'), 'And listed to fill.');
			Assert.areEqual(1, [SELECT COUNT() FROM Connector_Recipe__c WITH SYSTEM_MODE], 'Import saves nothing.');
		}
	}

	@IsTest
	static void aTemplateOffersALockedConnectionAndDraftsAndStoresNothing() {
		System.runAs(admin()) {
			Test.startTest();
			ConnectorRecipeFiles.Imported result = ConnectorRecipesController.importFile(JSON.serialize(template()));
			Test.stopTest();

			Assert.areEqual(ConnectorRecipeFiles.TEMPLATE, result.kind);
			Assert.areEqual('Mailchimp', result.connection.label);
			Assert.areEqual(ConnectorConnections.BASIC, result.connection.authKind);
			Assert.areEqual('https://{dc}.api.mailchimp.com/3.0', result.connection.baseUrl);
			Assert.areEqual('^[a-z]{2}[0-9]{1,3}$', result.connection.urlParams[0].pattern);
			Map<String, Object> step = (Map<String, Object>) ((List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(
					result.recipes[0].draftJson
				))
				.get('steps'))[0];
			Assert.areEqual('POST', step.get('method'), 'The action is copied into the step.');
			Assert.areEqual('/lists/{listId}', step.get('path'));
			Assert.isFalse(step.containsKey('action'), 'The recipe no longer needs the template.');
			Assert.areEqual(new List<Object>{ 'pathValues', 'connection' }, step.get('fill'));
			Assert.areEqual(0, [SELECT COUNT() FROM Connector_Recipe__c WITH SYSTEM_MODE], 'Nothing is stored.');
		}
	}

	@IsTest
	static void importRefusesMergeFieldsSecretsFormulasAndUnsafeAddresses() {
		System.runAs(admin()) {
			Map<String, Object> plainHttp = template();
			plainHttp.put('baseUrl', 'http://{dc}.api.mailchimp.com/3.0');
			Map<String, Object> hostInPath = template();
			hostInPath.put('baseUrl', 'https://api.mailchimp.com/{dc}');
			Map<String, Object> extraKey = template();
			extraKey.put('extra', true);
			Map<String, Object> missing = template();
			missing.put('requires', new List<Object>{ 'No_Such_Object__c' });
			Map<String, Object> unknownKind = template();
			((Map<String, Object>) unknownKind.get('auth')).put('kind', 'MagicSignIn');
			Map<String, Object> headerTemplate = template();
			((Map<String, Object>) headerTemplate.get('auth')).put('headerTemplate', 'X');
			Map<String, Object> bodyFormulas = template();
			bodyFormulas.put('webhook', new Map<String, Object>{ 'allowMergeFieldsInBody' => true });
			Map<String, Object> apiKey = template();
			apiKey.put('webhook', new Map<String, Object>{ 'apiKey' => 'abc' });
			Map<String, Object> bearer = template();
			bearer.put('description', 'Bearer abcdef1234567890');

			Test.startTest();
			String mergeField = refusal('{"barnRecipe":1,"recipe":{"note":"{!$Credential.Barn_Stripe.Key}"}}');
			String escaped = refusal('{"key":"a","label":"A","version":1,"description":"\\u007b!$Credential.X.Y}"}');
			String http = refusal(JSON.serialize(plainHttp));
			String path = refusal(JSON.serialize(hostInPath));
			String extra = refusal(JSON.serialize(extraKey));
			String needs = refusal(JSON.serialize(missing));
			String kind = refusal(JSON.serialize(unknownKind));
			String header = refusal(JSON.serialize(headerTemplate));
			String formula = refusal(JSON.serialize(bodyFormulas));
			String secret = refusal(JSON.serialize(apiKey));
			String signIn = refusal(JSON.serialize(bearer));
			Test.stopTest();

			Assert.areEqual(expected('Connector_Import_ErrorMergeField', ''), mergeField);
			Assert.areEqual(expected('Connector_Import_ErrorMergeField', ''), escaped);
			Assert.areEqual(expected('Connector_Import_ErrorUrl', 'http://{dc}.api.mailchimp.com/3.0'), http);
			Assert.areEqual(expected('Connector_Import_ErrorUrl', 'https://api.mailchimp.com/{dc}'), path);
			Assert.areEqual(expected('Connector_Import_ErrorKey', 'extra'), extra);
			Assert.areEqual(expected('Connector_Import_ErrorMissing', 'No_Such_Object__c'), needs);
			Assert.areEqual(expected('Connector_Import_ErrorAuth', 'MagicSignIn'), kind);
			Assert.areEqual(expected('Connector_Import_ErrorFormula', 'headerTemplate'), header);
			Assert.areEqual(expected('Connector_Import_ErrorFormula', 'allowMergeFieldsInBody'), formula);
			Assert.areEqual(expected('Connector_Import_ErrorSecret', 'apiKey'), secret);
			Assert.areEqual(expected('Connector_Import_ErrorSecret', 'Bearer'), signIn);
			Assert.isFalse(signIn.contains('abcdef1234567890'), 'A refusal never repeats the secret (F7).');
		}
	}

	@IsTest
	static void samCannotImport() {
		User sam = TestUsers.standardUserWith('Sam', new List<String>{ VIEWER_SET });
		System.runAs(sam) {
			Test.startTest();
			String refused = refusal(JSON.serialize(template()));
			String direct;
			try {
				ConnectorRecipeFiles.read(JSON.serialize(template()));
			} catch (Exception failure) {
				direct = failure.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Error_NoManage'), refused);
			Assert.areEqual(refused, direct, 'The page refuses as Apex does.');
		}
	}
}
