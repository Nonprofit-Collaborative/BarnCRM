/**
 * Advanced Reporting's query service: each viewer sees only what their own access allows, groups
 * and totals are SOQL built from checked names, large reports page in Id order, and nothing the
 * browser sends can change the query's shape.
 */
@IsTest(testFor='ApexClass:ReportingQueryService')
private class ReportingQueryServiceTest {
	private static final List<String> FIND_AND_REPORT = new List<String>{
		'BarnCRM_Find_And_Export',
		'Reporting_Staff'
	};

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith('Reporting_Admin');
		TestUsers.standardUserWith('Ana', FIND_AND_REPORT);
		TestUsers.standardUserWith('Ben', FIND_AND_REPORT);
		TestUsers.standardUserWith('Cal', new List<String>{ 'Reporting_Staff' });
	}

	private static User cal() {
		return TestUsers.fromSetup('Cal');
	}

	private static Map<String, Object> query(String objectName, List<String> fields) {
		return new Map<String, Object>{ 'version' => 1, 'object' => objectName, 'fields' => fields, 'limit' => 200 };
	}

	private static String request(Map<String, Object> query, Map<String, Object> extra) {
		Map<String, Object> raw = new Map<String, Object>{ 'query' => query };
		raw.putAll(extra);
		return JSON.serialize(raw);
	}

	private static List<Account> organizations(Integer howMany) {
		List<Account> accounts = new List<Account>();
		for (Integer i = 0; i < howMany; i++) {
			accounts.add(
				TestDataFactory.organization(new Account(Name = 'Org ' + i, NumberOfEmployees = 10 * (i + 1)))
			);
		}
		insert accounts;
		return accounts;
	}

	@IsTest
	static void theObjectListHoldsCustomObjectsAndThreeStandardOnesButNoSettings() {
		System.runAs(TestUsers.adminWith('Reporting_Admin')) {
			Set<String> names = new Set<String>();
			for (Map<String, String> option : ReportingQueryService.listObjects()) {
				names.add(option.get('value'));
			}
			Assert.isTrue(names.contains('Account'), 'Account is offered');
			Assert.isTrue(names.contains('Contact'), 'Contact is offered');
			Assert.isTrue(names.contains(NamespaceUtil.qualify('Saved_Query__c')), 'A custom object');
			Assert.isFalse(names.contains(NamespaceUtil.qualify('BarnCRM_Settings__c')), 'A custom setting is not');
			Assert.isFalse(names.contains('Group'), 'Other standard objects are not');

			Boolean contactsFound = false;
			for (Map<String, String> child : ReportingQueryService.listChildren('Account')) {
				contactsFound |= child.get('object') == 'Contact' && child.get('field') == 'AccountId';
			}
			Assert.isTrue(contactsFound, 'A Contact is a related record of an Account');
		}
	}

	@IsTest
	static void eachViewerSeesOnlyTheRecordsTheirAccessAllows() {
		User ana = TestUsers.fromSetup('Ana');
		User ben = TestUsers.fromSetup('Ben');
		System.runAs(ana) {
			insert new Saved_Query__c(Name = 'Ana Query', Object_Name__c = 'Contact');
		}
		System.runAs(ben) {
			insert new Saved_Query__c(Name = 'Ben Query', Object_Name__c = 'Contact');
			String table = request(query('Saved_Query__c', new List<String>{ 'Name' }), new Map<String, Object>());
			List<SObject> rows = (List<SObject>) ReportingQueryService.run(table).get('rows');
			Assert.areEqual(1, rows.size(), 'Saved queries are private: Ben sees his own only');
			Assert.areEqual('Ben Query', rows[0].get('Name'), 'His own');

			String grouped = request(
				query('Saved_Query__c', new List<String>{ 'Name' }),
				new Map<String, Object>{
					'groups' => new List<Object>{ new Map<String, Object>{ 'field' => 'Object_Name__c' } },
					'measures' => new List<Object>{ new Map<String, Object>{ 'fn' => 'count' } }
				}
			);
			List<Object> groups = (List<Object>) ReportingQueryService.run(grouped).get('groups');
			Assert.areEqual(1, groups.size(), 'One group');
			Assert.areEqual(
				1,
				((List<Object>) ((Map<String, Object>) groups[0]).get('values'))[0],
				'Counted in his access only'
			);
		}
		System.runAs(cal()) {
			Boolean refused = false;
			try {
				ReportingQueryService.run(
					request(query('Saved_Query__c', new List<String>{ 'Name' }), new Map<String, Object>())
				);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Assert.isTrue(refused, 'Cal cannot read saved queries, so the report is refused');
		}
	}

	@IsTest
	static void groupsTotalByLookupNameAndDateBucket() {
		System.runAs(TestUsers.adminWith('Reporting_Admin')) {
			organizations(2);
			Map<String, Object> result = ReportingQueryService.run(
				request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{
						'groups' => new List<Object>{ new Map<String, Object>{ 'field' => 'OwnerId' } },
						'measures' => new List<Object>{
							new Map<String, Object>{ 'fn' => 'count' },
							new Map<String, Object>{ 'fn' => 'avg', 'path' => 'NumberOfEmployees' }
						}
					}
				)
			);
			List<Object> groups = (List<Object>) result.get('groups');
			Assert.areEqual(1, groups.size(), 'One owner');
			Map<String, Object> owner = (Map<String, Object>) groups[0];
			Assert.areEqual(
				UserInfo.getName(),
				((List<Object>) owner.get('labels'))[0],
				'Grouped by the lookup and named, not shown as an Id'
			);
			Assert.areEqual(
				UserInfo.getUserId(),
				((List<Object>) ((List<Object>) owner.get('keys'))[0])[0],
				'The key is the Id'
			);
			Assert.areEqual(2, ((List<Object>) owner.get('values'))[0], 'Two organizations');
			Assert.areEqual(
				15,
				((Decimal) ((List<Object>) owner.get('values'))[1]).intValue(),
				'Average of ten and twenty'
			);
			Assert.isFalse((Boolean) result.get('more'), 'All groups returned');

			Map<String, Object> total = ReportingQueryService.run(
				request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{
						'measures' => new List<Object>{
							new Map<String, Object>{ 'fn' => 'sum', 'path' => 'NumberOfEmployees' }
						}
					}
				)
			);
			List<Object> totalRows = (List<Object>) total.get('groups');
			Assert.areEqual(1, totalRows.size(), 'A total with no grouping is one row');
			Assert.areEqual(
				30,
				((Decimal) ((List<Object>) ((Map<String, Object>) totalRows[0]).get('values'))[0]).intValue(),
				'The metric'
			);

			Map<String, Object> byMonth = ReportingQueryService.run(
				request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{
						'groups' => new List<Object>{
							new Map<String, Object>{ 'field' => 'CreatedDate', 'bucket' => 'month' }
						},
						'measures' => new List<Object>{
							new Map<String, Object>{ 'fn' => 'sum', 'path' => 'NumberOfEmployees' },
							new Map<String, Object>{ 'fn' => 'max', 'path' => 'CreatedDate' }
						}
					}
				)
			);
			Map<String, Object> month = (Map<String, Object>) ((List<Object>) byMonth.get('groups'))[0];
			List<Object> keys = (List<Object>) ((List<Object>) month.get('keys'))[0];
			Assert.areEqual(2, keys.size(), 'A month is its year and its number');
			Assert.areEqual(Date.today().year(), keys[0], 'This year');
			Assert.areEqual(30, ((Decimal) ((List<Object>) month.get('values'))[0]).intValue(), 'Ten plus twenty');
		}
	}

	@IsTest
	static void aGroupedReportPastTheLimitIsScannedInIdOrder() {
		System.runAs(TestUsers.adminWith('Reporting_Admin')) {
			organizations(3);
			ReportingQueryService.aggregateRecordLimit = 2;
			Map<String, Object> accounts = query('Account', new List<String>{ 'Name' });
			Map<String, Object> grouped = ReportingQueryService.run(
				request(
					accounts,
					new Map<String, Object>{
						'groups' => new List<Object>{ new Map<String, Object>{ 'field' => 'Name' } },
						'measures' => new List<Object>{ new Map<String, Object>{ 'fn' => 'count' } }
					}
				)
			);
			Assert.isTrue((Boolean) grouped.get('scan'), 'Too many to total in one query');

			String pageRequest = request(
				accounts,
				new Map<String, Object>{
					'groups' => new List<Object>{ new Map<String, Object>{ 'field' => 'OwnerId' } },
					'measures' => new List<Object>{
						new Map<String, Object>{ 'fn' => 'sum', 'path' => 'NumberOfEmployees' }
					},
					'fields' => new List<Object>{ 'Description' }
				}
			);
			Map<String, Object> first = ReportingQueryService.page(pageRequest, null, 2, false);
			List<SObject> firstRows = (List<SObject>) first.get('rows');
			Assert.areEqual(2, firstRows.size(), 'A page of two');
			Assert.isFalse((Boolean) first.get('done'), 'More to read');
			Assert.isFalse(
				firstRows[0].isSet('Description'),
				'A scan reads only the fields its groupings and totals use'
			);
			Assert.isNotNull(
				firstRows[0].getSObject('Owner').get('Name'),
				'The grouping lookup is read with its record name'
			);
			Map<String, Object> second = ReportingQueryService.page(
				pageRequest,
				String.valueOf(first.get('lastId')),
				2,
				false
			);
			List<SObject> secondRows = (List<SObject>) second.get('rows');
			Assert.areEqual(1, secondRows.size(), 'The rest');
			Assert.isTrue((Boolean) second.get('done'), 'Finished');
			Assert.isTrue(
				String.valueOf(secondRows[0].Id) > String.valueOf(firstRows[1].Id),
				'In Id order after the last one read'
			);
			Assert.isNotNull(secondRows[0].get('NumberOfEmployees'), 'The totalled field is read');
		}
	}

	@IsTest
	static void exportNeedsExportReportsAndReadsEachColumnOnce() {
		for (User person : new List<User>{ TestUsers.adminWith('Reporting_Admin'), cal() }) {
			System.runAs(person) {
				String exportRequest = request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{ 'fields' => new List<Object>{ 'Name', 'name', 'ID', 'NumberOfEmployees' } }
				);
				Boolean allowed = ReportingQueryService.canExport();
				Boolean refused = false;
				try {
					Map<String, Object> exported = ReportingQueryService.page(exportRequest, null, null, true);
					Assert.isNotNull(exported.get('rows'), 'A page of rows');
				} catch (AuraHandledException e) {
					refused = true;
				}
				Assert.areEqual(!allowed, refused, 'Export follows Export Reports');
				refused = false;
				try {
					ReportingQueryService.page(exportRequest, null, null, false);
				} catch (AuraHandledException e) {
					refused = true;
				}
				Assert.isTrue(refused, 'A list is never read in pages without the export flag');
			}
		}
		List<Object> tooMany = new List<Object>();
		for (Integer i = 0; i <= ReportingQueryService.MAX_FIELDS; i++) {
			tooMany.add('Name');
		}
		Boolean refused = false;
		try {
			ReportingQueryService.read(
				request(query('Account', new List<String>{ 'Name' }), new Map<String, Object>{ 'fields' => tooMany })
			);
		} catch (ReportingQueryService.ReportingException e) {
			refused = true;
		}
		Assert.isTrue(refused, 'At most 20 columns');
	}

	@IsTest
	static void relatedTotalsCountTheChildRecordsOfEachRow() {
		System.runAs(TestUsers.adminWith('Reporting_Admin')) {
			organizations(2);
			Map<String, Object> people = query('User', new List<String>{ 'Name' });
			people.put(
				'filter',
				new Map<String, Object>{
					'version' => 1,
					'conditions' => new List<Object>{
						new Map<String, Object>{
							'id' => 1,
							'field' => 'Id',
							'operator' => 'equals',
							'value' => UserInfo.getUserId()
						}
					}
				}
			);
			Map<String, Object> result = ReportingQueryService.run(
				request(
					people,
					new Map<String, Object>{
						'summaries' => new List<Object>{
							new Map<String, Object>{ 'object' => 'Account', 'field' => 'OwnerId', 'fn' => 'count' },
							new Map<String, Object>{
								'object' => 'Account',
								'field' => 'OwnerId',
								'fn' => 'sum',
								'path' => 'NumberOfEmployees',
								'filter' => new Map<String, Object>{
									'version' => 1,
									'conditions' => new List<Object>{
										new Map<String, Object>{
											'id' => 1,
											'field' => 'Name',
											'operator' => 'equals',
											'value' => 'Org 1'
										}
									}
								}
							}
						}
					}
				)
			);
			List<Object> summaries = (List<Object>) result.get('summaries');
			String me = String.valueOf(UserInfo.getUserId());
			Assert.areEqual(2, ((Map<String, Object>) summaries[0]).get(me), 'Two organizations');
			Assert.areEqual(
				20,
				((Decimal) ((Map<String, Object>) summaries[1]).get(me)).intValue(),
				'Only the one its own filter keeps'
			);
		}
	}

	@IsTest
	static void nothingTheBrowserSendsChangesTheQueryShape() {
		System.runAs(TestUsers.adminWith('Reporting_Admin')) {
			organizations(1);
			List<String> attempts = new List<String>{
				'not json',
				'{"query": "SELECT Id FROM Account"}',
				request(query('Account WHERE Name != null', new List<String>{ 'Name' }), new Map<String, Object>()),
				request(query('Group', new List<String>{ 'Name' }), new Map<String, Object>()),
				request(
					query(NamespaceUtil.qualify('BarnCRM_Settings__c'), new List<String>{ 'Name' }),
					new Map<String, Object>()
				),
				request(query('Account', new List<String>{ 'Name) FROM User --' }), new Map<String, Object>()),
				request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{
						'groups' => new List<Object>{
							new Map<String, Object>{ 'field' => 'Name, (SELECT Id FROM Account)' }
						},
						'measures' => new List<Object>{ new Map<String, Object>{ 'fn' => 'count' } }
					}
				),
				request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{
						'groups' => new List<Object>{
							new Map<String, Object>{ 'field' => 'CreatedDate', 'bucket' => 'month) FROM User --' }
						},
						'measures' => new List<Object>{ new Map<String, Object>{ 'fn' => 'count' } }
					}
				),
				request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{
						'groups' => new List<Object>{ new Map<String, Object>{ 'field' => 'Name' } },
						'measures' => new List<Object>{
							new Map<String, Object>{ 'fn' => 'SUM(Id) x, COUNT', 'path' => 'Id' }
						}
					}
				),
				request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{
						'groups' => new List<Object>{ new Map<String, Object>{ 'field' => 'Name' } },
						'measures' => new List<Object>{ new Map<String, Object>{ 'fn' => 'sum', 'path' => 'Name' } }
					}
				),
				request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{
						'groups' => new List<Object>{ new Map<String, Object>{ 'field' => 'Name' } }
					}
				),
				request(
					query('Account', new List<String>{ 'Name' }),
					new Map<String, Object>{
						'summaries' => new List<Object>{
							new Map<String, Object>{ 'object' => 'Contact', 'field' => 'OwnerId', 'fn' => 'count' }
						}
					}
				)
			};
			Integer refused = 0;
			for (String attempt : attempts) {
				try {
					ReportingQueryService.run(attempt);
				} catch (AuraHandledException e) {
					refused++;
				}
			}
			Assert.areEqual(attempts.size(), refused, 'Every attempt is refused');

			Boolean badCursor = false;
			try {
				ReportingQueryService.page(
					request(
						query('Account', new List<String>{ 'Name' }),
						new Map<String, Object>{
							'measures' => new List<Object>{ new Map<String, Object>{ 'fn' => 'count' } }
						}
					),
					'001\' OR Id != null',
					10,
					false
				);
			} catch (AuraHandledException e) {
				badCursor = true;
			}
			Assert.isTrue(badCursor, 'A cursor that is not an Id is refused');

			Map<String, Object> quoted = query('Account', new List<String>{ 'Name' });
			quoted.put(
				'filter',
				new Map<String, Object>{
					'version' => 1,
					'conditions' => new List<Object>{
						new Map<String, Object>{
							'id' => 1,
							'field' => 'Name',
							'operator' => 'equals',
							'value' => 'x\' OR Name != \'y'
						}
					}
				}
			);
			List<SObject> rows = (List<SObject>) ReportingQueryService.run(request(quoted, new Map<String, Object>()))
				.get('rows');
			Assert.areEqual(0, rows.size(), 'A quoted value is a bound value, not SOQL');
		}
	}
}
