/**
 * Saved maps and the Mapper's server half (canonical model R-MAP1 to R-MAP4, R-ST5): the shared
 * fixture's documents are accepted and refused as the screen's module accepts and refuses them;
 * a map saves, changes in place, renames and deletes; maps and step lists never see each other;
 * the preview runs steps, fixed values, defaults and lookups as the person; Where Used finds a
 * map by the fields it names and asks the modules which tools link it; a person without Manage
 * BarnCRM Settings may list and load maps but not change or check them.
 */
@IsTest(testFor='ApexClass:MapController, ApexClass:SavedTransformService, ApexClass:WhereUsedService')
private class MapControllerTest {
	@TestSetup
	static void setUp() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.createUser('Joel', new List<String>{ 'BarnCRM_Find_And_Export', 'BarnCRM_Bulk_Update' });
		}
	}

	private static User joel() {
		return [SELECT Id FROM User WHERE Username LIKE 'barn-test.joel.%' LIMIT 1];
	}

	private static Map<String, Object> fixture() {
		StaticResource resource = [SELECT Body FROM StaticResource WHERE Name = 'MapDocumentFixture' LIMIT 1];
		return (Map<String, Object>) JSON.deserializeUntyped(resource.Body.toString());
	}

	private static String toContact(List<Object> columns, List<Object> defaults) {
		return JSON.serialize(
			new Map<String, Object>{
				'version' => 4,
				'from' => new Map<String, Object>{ 'kind' => 'columns' },
				'to' => new Map<String, Object>{ 'kind' => 'record', 'object' => 'Contact' },
				'columns' => columns,
				'defaults' => defaults
			}
		);
	}

	private static Map<String, Object> column(String source, String target) {
		return new Map<String, Object>{ 'source' => source, 'target' => target };
	}

	private static String refusal(String definitionJson) {
		try {
			MapController.saveMap(null, 'Refused', definitionJson);
			return null;
		} catch (AuraHandledException refused) {
			return refused.getMessage();
		}
	}

	private static Map<String, MapController.PreviewValue> byTarget(MapController.PreviewSample sample) {
		Map<String, MapController.PreviewValue> values = new Map<String, MapController.PreviewValue>();
		for (MapController.PreviewValue value : sample.values) {
			values.put(value.target, value);
		}
		return values;
	}

	@IsTest
	static void theFixtureIsAcceptedAndRefusedAsTheScreenDoes() {
		System.runAs(TestUsers.admin()) {
			Map<String, Object> cases = fixture();
			for (Object each : (List<Object>) cases.get('valid')) {
				Map<String, Object> valid = (Map<String, Object>) each;
				SavedTransformService.checkMap(JSON.serialize(valid.get('document')));
			}
			for (Object each : (List<Object>) cases.get('invalid')) {
				Map<String, Object> invalid = (Map<String, Object>) each;
				try {
					SavedTransformService.checkMap(JSON.serialize(invalid.get('document')));
					Assert.fail('Refused: ' + invalid.get('name'));
				} catch (BulkUpdateFields.BulkUpdateException refused) {
					Assert.isNotNull(refused.getMessage(), (String) invalid.get('name'));
				}
			}
			for (Object path : (List<Object>) ((Map<String, Object>) cases.get('paths')).get('valid')) {
				Assert.isTrue(SavedTransformService.isPath((String) path), (String) path);
			}
			for (Object path : (List<Object>) ((Map<String, Object>) cases.get('paths')).get('invalid')) {
				Assert.isFalse(SavedTransformService.isPath((String) path), (String) path);
			}
		}
	}

	@IsTest
	static void aMapSavesChangesInPlaceRenamesAndDeletes() {
		System.runAs(TestUsers.admin()) {
			String first = toContact(new List<Object>{ column('E-mail', 'Record.Email') }, new List<Object>());
			SavedTransformService.SavedList saved = MapController.saveMap(null, '  Sign-ups  ', first);
			Assert.areEqual('Sign-ups', saved.name);
			Assert.areEqual('Contact', saved.objectName);
			Assert.areEqual(
				SavedTransformService.KIND_MAP,
				[SELECT Kind__c FROM Saved_Transform__c WHERE Id = :saved.recordId WITH USER_MODE].Kind__c
			);

			String second = toContact(
				new List<Object>{ column('E-mail', 'Record.Email'), column('Surname', 'Record.LastName') },
				new List<Object>()
			);
			SavedTransformService.SavedList changed = MapController.saveMap(saved.recordId, 'Sign-ups', second);
			Assert.areEqual(saved.recordId, changed.recordId, 'A map changes in place; tools link it by ID.');
			Assert.areEqual(second, MapController.loadMap(saved.recordId).definitionJson);

			MapController.renameMap(saved.recordId, 'Event sign-ups');
			List<SavedTransformService.ListEntry> maps = MapController.listMaps();
			Assert.areEqual(1, maps.size());
			Assert.areEqual('Event sign-ups', maps[0].name);
			Assert.areEqual('Contact', maps[0].objectLabel);

			MapController.deleteMap(saved.recordId);
			Assert.areEqual(0, MapController.listMaps().size());
		}
	}

	@IsTest
	static void mapsAndStepListsNeverSeeEachOther() {
		System.runAs(TestUsers.admin()) {
			SavedTransformService.SavedList stepList = SavedTransformService.save(
				'Tidy',
				'{"version":1,"object":"Contact","changes":[{"field":"Title","action":"set","value":"Coordinator"}]}'
			);
			SavedTransformService.SavedList savedMap = MapController.saveMap(
				null,
				'Tidy',
				toContact(new List<Object>{ column('Title', 'Record.Title') }, new List<Object>())
			);

			Assert.areEqual(1, SavedTransformService.listAll().size(), 'A map is not a step list.');
			Assert.areEqual(stepList.recordId, SavedTransformService.listAll()[0].recordId);
			Assert.areEqual(1, MapController.listMaps().size(), 'A step list is not a map.');
			Assert.areEqual(savedMap.recordId, MapController.listMaps()[0].recordId);
			try {
				MapController.loadMap(stepList.recordId);
				Assert.fail('A step list is not opened as a map.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(BarnHelp.text('Core', 'Core_Map_ErrorNotFound'), refused.getMessage());
			}
			try {
				SavedTransformService.load(savedMap.recordId);
				Assert.fail('A map is not opened as a step list.');
			} catch (BulkUpdateFields.BulkUpdateException refused) {
				Assert.isNotNull(refused.getMessage());
			}
		}
	}

	@IsTest
	static void aNameOrDocumentThatIsNotUsableIsRefused() {
		System.runAs(TestUsers.admin()) {
			String usable = toContact(new List<Object>{ column('E-mail', 'Record.Email') }, new List<Object>());
			MapController.saveMap(null, 'Sign-ups', usable);
			try {
				MapController.saveMap(null, 'SIGN-UPS', usable);
				Assert.fail('A name is unique among maps, capitals ignored.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_Map_ErrorExists', new List<Object>{ 'SIGN-UPS' }),
					refused.getMessage()
				);
			}
			try {
				MapController.saveMap(null, ' ', usable);
				Assert.fail('A blank name is refused.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_Map_ErrorName', new List<Object>{ SavedTransformService.MAX_NAME }),
					refused.getMessage()
				);
			}
			Assert.areEqual(BarnHelp.text('Core', 'Core_Map_ErrorUnreadable'), refusal('{not json'));
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_Map_ErrorTargetTwice', new List<Object>{ 'Record.email' }),
				refusal(
					toContact(
						new List<Object>{ column('a', 'Record.Email'), column('b', 'Record.email') },
						new List<Object>()
					)
				)
			);
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_Map_ErrorColumn', new List<Object>{ 1 }),
				refusal(toContact(new List<Object>{ new Map<String, Object>{ 'source' => 'a' } }, new List<Object>()))
			);
			List<Object> tooMany = new List<Object>();
			for (Integer i = 0; i <= SavedTransformService.MAX_MAP_COLUMNS; i++) {
				tooMany.add(column('c' + i, 'Record.F' + i));
			}
			Assert.areEqual(
				BarnHelp.text(
					'Core',
					'Core_Map_ErrorTooMany',
					new List<Object>{ SavedTransformService.MAX_MAP_COLUMNS, SavedTransformService.MAX_MAP_DEFAULTS }
				),
				refusal(toContact(tooMany, new List<Object>()))
			);
			Assert.areEqual(1, MapController.listMaps().size(), 'Nothing refused was saved.');
		}
	}

	@IsTest
	static void thePreviewRunsStepsFixedValuesDefaultsAndLookups() {
		System.runAs(TestUsers.admin()) {
			Account found = TestDataFactory.organization(new Account(Name = 'Riverside Food Bank'));
			insert as user new List<Account>{
				found,
				TestDataFactory.organization(new Account(Name = 'Twin')),
				TestDataFactory.organization(new Account(Name = 'Twin'))
			};
			Map<String, Object> email = column('profile.email', 'Record.Email');
			email.put(
				'transforms',
				new List<Object>{
					new Map<String, Object>{ 'op' => 'trim' },
					new Map<String, Object>{ 'op' => 'lower' }
				}
			);
			Map<String, Object> account = column('order.company', 'Record.AccountId');
			account.put(
				'lookup',
				new Map<String, Object>{ 'object' => 'Account', 'field' => 'Name', 'notFound' => 'leaveEmpty' }
			);
			Map<String, Object> description = new Map<String, Object>{
				'value' => 'Eventbrite',
				'target' => 'Record.Description'
			};
			Map<String, Object> title = column('profile.title', 'Record.Title');
			String definition = toContact(
				new List<Object>{ email, account, description, title },
				new List<Object>{
					new Map<String, Object>{ 'target' => 'Record.Title', 'value' => 'Guest' },
					new Map<String, Object>{ 'target' => 'Record.LeadSource', 'value' => 'Web' }
				}
			);
			String samples = JSON.serialize(
				new List<Object>{
					new Map<String, Object>{
						'profile.email' => '  Pat@Example.ORG ',
						'order.company' => 'riverside food bank',
						'profile.title' => 'Chair'
					},
					new Map<String, Object>{ 'profile.email' => 'x@y.org', 'order.company' => 'Twin' },
					new Map<String, Object>{ 'profile.email' => 'z@y.org', 'order.company' => 'Nobody' }
				}
			);

			MapController.Preview preview = MapController.previewMap(definition, samples);

			Assert.areEqual(3, preview.samples.size());
			Map<String, MapController.PreviewValue> first = byTarget(preview.samples[0]);
			Assert.areEqual('pat@example.org', first.get('Record.Email').value, 'The steps run.');
			Assert.areEqual('Eventbrite', first.get('Record.Description').value, 'A fixed value is used.');
			Assert.areEqual('Chair', first.get('Record.Title').value);
			Assert.areEqual('Web', first.get('Record.LeadSource').value, 'A default with no column fills.');
			Assert.areEqual('found', first.get('Record.AccountId').lookup, 'Capitals are ignored.');
			Map<String, MapController.PreviewValue> second = byTarget(preview.samples[1]);
			Assert.areEqual('Guest', second.get('Record.Title').value, 'A blank value takes the default.');
			Assert.areEqual('several', second.get('Record.AccountId').lookup);
			Assert.areEqual('none', byTarget(preview.samples[2]).get('Record.AccountId').lookup);
		}
	}

	@IsTest
	static void aLookupByRecordIdAndOneByAFieldThatCannotBeFilteredAreHandled() {
		System.runAs(TestUsers.admin()) {
			Account parent = TestDataFactory.organization(new Account(Name = 'Parent'));
			insert as user parent;
			Map<String, Object> byId = column('org', 'Record.AccountId');
			byId.put('lookup', new Map<String, Object>{ 'object' => 'Account', 'field' => 'Id' });
			String samples = JSON.serialize(
				new List<Object>{
					new Map<String, Object>{ 'org' => String.valueOf(parent.Id).left(15) },
					new Map<String, Object>{ 'org' => 'not an id' }
				}
			);
			MapController.Preview preview = MapController.previewMap(
				toContact(new List<Object>{ byId }, new List<Object>()),
				samples
			);
			Assert.areEqual(
				'found',
				byTarget(preview.samples[0]).get('Record.AccountId').lookup,
				'15 or 18 characters.'
			);
			Assert.areEqual('none', byTarget(preview.samples[1]).get('Record.AccountId').lookup);

			Map<String, Object> byText = column('org', 'Record.AccountId');
			byText.put('lookup', new Map<String, Object>{ 'object' => 'Account', 'field' => 'Description' });
			try {
				MapController.previewMap(toContact(new List<Object>{ byText }, new List<Object>()), samples);
				Assert.fail('A long text field cannot be looked up by.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Core', 'Core_Map_ErrorLookup', new List<Object>{ 'Description', 'Account' }),
					refused.getMessage()
				);
			}
		}
	}

	@IsTest
	static void lookupsByTheSameFieldShareOneQueryAndTooManyFieldsAreRefused() {
		System.runAs(TestUsers.admin()) {
			insert as user TestDataFactory.organization(new Account(Name = 'Riverside Food Bank'));
			Map<String, Object> byName = new Map<String, Object>{ 'object' => 'Account', 'field' => 'Name' };
			Map<String, Object> account = column('org', 'Record.AccountId');
			account.put('lookup', byName);
			Map<String, Object> reportsTo = column('other', 'Record.ReportsToId');
			reportsTo.put('lookup', byName);
			String samples = JSON.serialize(
				new List<Object>{ new Map<String, Object>{ 'org' => 'Riverside Food Bank', 'other' => 'Nobody' } }
			);
			// Warm the help catalog and describe so only the lookups' queries are counted.
			MapController.previewMap(toContact(new List<Object>{ account }, new List<Object>()), samples);
			Integer before = Limits.getQueries();
			MapController.previewMap(toContact(new List<Object>{ account }, new List<Object>()), samples);
			Integer one = Limits.getQueries() - before;
			before = Limits.getQueries();
			MapController.Preview preview = MapController.previewMap(
				toContact(new List<Object>{ account, reportsTo }, new List<Object>()),
				samples
			);
			Assert.areEqual(one, Limits.getQueries() - before, 'Two columns found by Account Name share a query.');
			Assert.areEqual('found', byTarget(preview.samples[0]).get('Record.AccountId').lookup);
			Assert.areEqual('none', byTarget(preview.samples[0]).get('Record.ReportsToId').lookup);

			List<Object> columns = new List<Object>();
			for (Integer i = 0; i <= MapController.MAX_LOOKUP_FIELDS; i++) {
				Map<String, Object> each = column('c' + i, 'Record.F' + i);
				each.put('lookup', new Map<String, Object>{ 'object' => 'Account', 'field' => 'F' + i });
				columns.add(each);
			}
			try {
				MapController.previewMap(toContact(columns, new List<Object>()), samples);
				Assert.fail('Too many lookup fields are refused.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text(
						'Core',
						'Core_Map_ErrorTooManyLookups',
						new List<Object>{ MapController.MAX_LOOKUP_FIELDS }
					),
					refused.getMessage()
				);
			}
		}
	}

	@IsTest
	static void theFieldsAndObjectsOfARecordMapAreThoseABulkUpdateMayWrite() {
		System.runAs(TestUsers.admin()) {
			Boolean sawContact = false;
			for (FindController.Option option : MapController.getObjects()) {
				Assert.isTrue(BulkUpdateFields.isWritable(option.value), option.value);
				sawContact = sawContact || option.value == 'Contact';
			}
			Assert.isTrue(sawContact);
			Boolean sawLastName = false;
			for (BulkUpdateFields.Target field : MapController.getTargetFields('Contact')) {
				if (field.apiName == 'LastName') {
					sawLastName = true;
					Assert.isTrue(field.required, 'A new Contact needs a last name.');
					Assert.areEqual(80, field.length);
				}
			}
			Assert.isTrue(sawLastName);
		}
	}

	@IsTest
	static void whereUsedFindsAMapAndAsksTheModulesWhoLinksIt() {
		System.runAs(TestUsers.admin()) {
			WhereUsedExtensions.noneForTest = true;
			MatchSourceSelector.allSourcesOverride = new List<Match_Source__mdt>();
			WhereUsedSelector.mergeRulesOverride = new List<Merge_Rule__mdt>();
			Map<String, Object> account = column('Org', 'Record.AccountId');
			account.put('lookup', new Map<String, Object>{ 'object' => 'Account', 'field' => 'Name' });
			String definition = JSON.serialize(
				new Map<String, Object>{
					'version' => 4,
					'to' => new Map<String, Object>{ 'kind' => 'record', 'object' => 'Contact' },
					'columns' => new List<Object>{ column('Job', 'Record.Department'), account },
					'defaults' => new List<Object>{
						new Map<String, Object>{ 'target' => 'Record.Title', 'value' => 'Guest' }
					},
					'match' => new Map<String, Object>{ 'by' => 'field', 'field' => 'Email' }
				}
			);
			SavedTransformService.SavedList saved = MapController.saveMap(null, 'Sign-ups', definition);

			Assert.areEqual(
				new List<String>{ String.format(System.Label.Core_WhereUsed_PartColumn, new List<Object>{ 'Job' }) },
				mapParts(WhereUsedService.find('Contact', 'Department'))
			);
			Assert.areEqual(
				new List<String>{ System.Label.Core_WhereUsed_PartDefault },
				mapParts(WhereUsedService.find('Contact', 'Title'))
			);
			Assert.areEqual(
				new List<String>{ System.Label.Core_WhereUsed_PartMatchingField },
				mapParts(WhereUsedService.find('Contact', 'Email'))
			);
			Assert.areEqual(
				new List<String>{ String.format(System.Label.Core_WhereUsed_PartColumn, new List<Object>{ 'Org' }) },
				mapParts(WhereUsedService.find('Account', 'Name')),
				'A lookup names its parent field.'
			);
			Assert.isTrue(mapParts(WhereUsedService.find('Contact', 'Phone')).isEmpty());

			Assert.areEqual(0, MapController.mapUsers(saved.recordId).size(), 'Core links no map.');
			WhereUsedExtensions.overrides.put('ProgramsWhereUsedExtension', new LinkingModule());
			List<WhereUsedService.Reference> users = MapController.mapUsers(saved.recordId);
			Assert.areEqual(1, users.size());
			Assert.areEqual('Webhook for Sign-ups', users[0].name);
		}
	}

	/** A module stand-in whose tool links any map it is asked about. */
	private class LinkingModule implements WhereUsedExtension {
		public List<WhereUsedService.Reference> references(WhereUsedService.Target target) {
			List<WhereUsedService.Reference> found = new List<WhereUsedService.Reference>();
			if (target.mapId != null && target.isMap(target.mapId)) {
				found.add(
					new WhereUsedService.Reference('connector', 'Connector', 'Webhook for ' + target.objectLabel, null)
				);
			}
			return found;
		}
	}

	private static List<String> mapParts(WhereUsedService.Result result) {
		for (WhereUsedService.Reference reference : result.references) {
			if (reference.kind == WhereUsedService.KIND_MAP) {
				return reference.parts;
			}
		}
		return new List<String>();
	}

	@IsTest
	static void aPersonWithoutManageSettingsMayReadMapsButNotChangeOrCheckThem() {
		Id mapId;
		System.runAs(TestUsers.admin()) {
			mapId = MapController.saveMap(
					null,
					'Sign-ups',
					toContact(new List<Object>{ column('E-mail', 'Record.Email') }, new List<Object>())
				)
				.recordId;
		}
		System.runAs(joel()) {
			Assert.areEqual(1, MapController.listMaps().size(), 'Every tool that uses a map reads it.');
			Assert.areEqual('Sign-ups', MapController.loadMap(mapId).name);
			String noPermission = BarnHelp.text('Core', 'Core_Map_ErrorNoPermission');
			for (Integer which = 0; which < 6; which++) {
				try {
					if (which == 0) {
						MapController.saveMap(mapId, 'Changed', '{"version":4}');
					} else if (which == 1) {
						MapController.renameMap(mapId, 'Changed');
					} else if (which == 2) {
						MapController.deleteMap(mapId);
					} else if (which == 3) {
						MapController.previewMap('{"version":4}', '[]');
					} else if (which == 4) {
						MapController.getTargetFields('Contact');
					} else {
						MapController.mapUsers(mapId);
					}
					Assert.fail('Refused: ' + which);
				} catch (AuraHandledException refused) {
					Assert.areEqual(noPermission, refused.getMessage(), 'Call ' + which);
				}
			}
		}
		System.runAs(TestUsers.admin()) {
			Assert.areEqual('Sign-ups', MapController.loadMap(mapId).name, 'Nothing changed.');
		}
	}
}
