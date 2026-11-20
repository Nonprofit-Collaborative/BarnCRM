/**
 * Dana builds recipes on Super Connector, and BarnCRM refuses a recipe that could smuggle a
 * merge field into a request or reach past its connection (CN-02; canonical model R-CR1;
 * security review F1 and F4).
 */
@IsTest(testFor='ApexClass:ConnectorRecipeDocument')
private class ConnectorRecipeDocumentTest {
	private static final String MAP_ID = 'a0B000000000001AAA';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ConnectorConnections.ADMIN_SET);
	}

	private static String call(String extra) {
		return ConnectorRecipeTestData.document(
			'[{"id":"send","kind":"callApp","connection":"' +
				ConnectorRecipeTestData.CONNECTION +
				'","method":"POST","path":"/contacts/{id}","pathValues":[{"name":"id","path":"trigger.id"}]' +
				extra +
				'}]'
		);
	}

	private static List<String> problems(String document) {
		return ConnectorRecipeDocument.problems(ConnectorRecipeDocument.parse(document));
	}

	@IsTest
	static void aMergeFieldAnywhereIsRefusedOnSaveEvenWhenEscaped() {
		System.runAs(TestUsers.adminWith(ConnectorConnections.ADMIN_SET)) {
			List<String> refusedDocuments = new List<String>{
				call(',"headers":[{"name":"X-Token","value":"{!$Credential.Password}"}]'),
				call(',"query":[{"name":"q","value":"{!$Api.Session_ID}"}]'),
				ConnectorRecipeTestData.document(
					'[{"id":"stop","kind":"stop","outcome":"Failed","message":"\\u007b!x}"}]'
				)
			};
			for (String document : refusedDocuments) {
				try {
					ConnectorRecipeDocument.parse(document);
					Assert.fail('A merge field must be refused: ' + document);
				} catch (ConnectorRecipeDocument.DocumentException refused) {
					Assert.areEqual(
						BarnHelp.text('Connector', 'Connector_Recipe_ErrorMergeField'),
						refused.getMessage()
					);
				}
			}
		}
	}

	@IsTest
	static void aGoodCallPassesAndBadPathsAreRefused() {
		System.runAs(TestUsers.adminWith(ConnectorConnections.ADMIN_SET)) {
			Assert.areEqual(new List<String>(), problems(call('')), 'A checked call passes.');
			for (
				String path : new List<String>{
					'//evil.example.com/x',
					'/a@evil.example.com',
					'/a\\\\b',
					'/a?b=1',
					'/a#b',
					'/a b',
					'contacts',
					'/a\\r\\nX-Injected: 1'
				}
			) {
				Assert.isTrue(
					ConnectorRecipeDocument.pathProblem((String) JSON.deserializeUntyped('"' + path + '"')),
					'Refused: ' + path
				);
			}
			Assert.isFalse(ConnectorRecipeDocument.pathProblem('/v1/contacts/{id}'));
		}
	}

	@IsTest
	static void signInHeadersBadValuesAndUnfilledSlotsAreRefused() {
		System.runAs(TestUsers.adminWith(ConnectorConnections.ADMIN_SET)) {
			String auth = problems(call(',"headers":[{"name":"Authorization","value":"Bearer x"}]'))[0];
			String newline = problems(call(',"headers":[{"name":"X-Note","value":"a\\nb"}]'))[0];
			String slot = problems(
				ConnectorRecipeTestData.document(
					'[{"id":"send","kind":"callApp","connection":"' +
						ConnectorRecipeTestData.CONNECTION +
						'","method":"GET","path":"/contacts/{id}"}]'
				)
			)[0];
			String blankSlot = problems(
				ConnectorRecipeTestData.document(
					'[{"id":"send","kind":"callApp","connection":"' +
						ConnectorRecipeTestData.CONNECTION +
						'","method":"GET","path":"/contacts/{id}","pathValues":[{"name":"id","path":"","value":""}]}]'
				)
			)[0];
			String other = problems(
				ConnectorRecipeTestData.document(
					'[{"id":"send","kind":"callApp","connection":"Other_Credential","method":"GET","path":"/x"}]'
				)
			)[0];

			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorHeader', new List<Object>{ 'send' }),
				auth
			);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorHeader', new List<Object>{ 'send' }),
				newline
			);
			Assert.areEqual(BarnHelp.text('Connector', 'Connector_Recipe_ErrorSlot', new List<Object>{ 'send' }), slot);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorSlot', new List<Object>{ 'send' }),
				blankSlot,
				'A path slot must be filled.'
			);
			Assert.areEqual(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorConnection', new List<Object>{ 'send' }),
				other,
				'Only a BarnCRM connection may be called.'
			);
		}
	}

	@IsTest
	static void stepsAreCheckedForShapeNamesNestingAndCount() {
		System.runAs(TestUsers.adminWith(ConnectorConnections.ADMIN_SET)) {
			String nested =
				'[{"id":"a","kind":"if","conditions":[{"path":"trigger.x","operator":"equals","value":"1"}],' +
				'"then":[{"id":"b","kind":"if","conditions":[{"path":"trigger.x","operator":"is null"}],' +
				'"then":[{"id":"c","kind":"if","conditions":[{"path":"trigger.x","operator":"is null"}],"then":[]}]}]}]';
			List<String> steps = new List<String>();
			for (Integer i = 0; i < 26; i++) {
				steps.add('{"id":"s' + i + '","kind":"stop","outcome":"Succeeded","message":""}');
			}

			Assert.isTrue(
				problems(ConnectorRecipeTestData.document(nested))
					.contains(BarnHelp.text('Connector', 'Connector_Recipe_ErrorNesting', new List<Object>{ 'c' }))
			);
			Assert.isTrue(
				problems(ConnectorRecipeTestData.document('[' + String.join(steps, ',') + ']'))
					.contains(BarnHelp.text('Connector', 'Connector_Recipe_ErrorTooManySteps'))
			);
			Assert.isTrue(
				problems(ConnectorRecipeTestData.document('[]'))
					.contains(BarnHelp.text('Connector', 'Connector_Recipe_ErrorNoSteps'))
			);
			Assert.areEqual(
				new List<String>{ BarnHelp.text('Connector', 'Connector_Recipe_ErrorStepId', new List<Object>{ 'x' }) },
				problems(
					ConnectorRecipeTestData.document(
						'[{"id":"x","kind":"stop","outcome":"Succeeded"},{"id":"x","kind":"stop","outcome":"Succeeded"}]'
					)
				),
				'Two steps cannot share a name.'
			);
			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorRecordId', new List<Object>{ 'u' })
				},
				problems(ConnectorRecipeTestData.document('[{"id":"u","kind":"update","map":"' + MAP_ID + '"}]'))
			);
			Assert.areEqual(
				new List<String>{
					BarnHelp.text('Connector', 'Connector_Recipe_ErrorStepKind', new List<Object>{ 'w' })
				},
				problems(ConnectorRecipeTestData.document('[{"id":"w","kind":"wait"}]')),
				'Steps of later slices are refused.'
			);
			Assert.areEqual(
				new Set<String>{ Id.valueOf(MAP_ID) },
				ConnectorRecipeDocument.mapIds(
					ConnectorRecipeDocument.parse(
						ConnectorRecipeTestData.document('[{"id":"m","kind":"create","map":"' + MAP_ID + '"}]')
					)
				)
			);
		}
	}

	@IsTest
	static void unreadableDocumentsAreRefused() {
		System.runAs(TestUsers.adminWith(ConnectorConnections.ADMIN_SET)) {
			for (String document : new List<String>{ '', 'not json', '[1,2]' }) {
				try {
					ConnectorRecipeDocument.parse(document);
					Assert.fail('Refused: ' + document);
				} catch (ConnectorRecipeDocument.DocumentException refused) {
					Assert.areEqual(
						BarnHelp.text('Connector', 'Connector_Recipe_ErrorUnreadable'),
						refused.getMessage()
					);
				}
			}
		}
	}
}
