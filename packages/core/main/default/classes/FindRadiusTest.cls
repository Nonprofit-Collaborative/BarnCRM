/**
 * Radius Find (C-69, canonical model R-SQ13): the shipped postal code table, the point a person
 * names, the condition the query document holds, and the records it keeps.
 */
@IsTest(testFor='ApexClass:FindRadius, ApexClass:QueryCompiler, ApexClass:FindController')
private class FindRadiusTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Contact contact(String lastName, Decimal latitude, Decimal longitude) {
		return new Contact(
			LastName = lastName,
			MailingPostalCode = '02134',
			MailingLatitude = latitude,
			MailingLongitude = longitude
		);
	}

	private static String document(Integer miles) {
		return '{"version": 1, "object": "Contact", "fields": ["LastName"], "radius": ' +
			'{"field": "MailingAddress", "miles": ' +
			miles +
			', "latitude": 42.3, "longitude": -71.1}}';
	}

	private static List<String> lastNames(List<SObject> rows) {
		List<String> names = new List<String>();
		for (SObject row : rows) {
			names.add((String) row.get('LastName'));
		}
		names.sort();
		return names;
	}

	@IsTest
	static void thePostalCodeTableShipsAndFindsABostonCode() {
		System.runAs(TestUsers.admin()) {
			FindRadius.Center boston = FindRadius.centroid('02134-1234');

			System.Assert.isNotNull(boston, 'The shipped table holds 02134.');
			System.Assert.isTrue(
				boston.latitude > 42 && boston.latitude < 43,
				'Boston is near 42.3: ' + boston.latitude
			);
			System.Assert.isTrue(boston.longitude < -70 && boston.longitude > -72, 'And -71.1.');
			System.Assert.isNull(FindRadius.centroid('00000'), 'A code with no ZCTA.');
			System.Assert.isNull(FindRadius.centroid('1234'), 'Not five digits.');
			System.Assert.isNull(FindRadius.centroid(null), 'Nothing typed.');
		}
	}

	@IsTest
	static void aPostalCodeReadsFromTheTableInTheRightPlace() {
		System.runAs(TestUsers.admin()) {
			FindRadius.tableForTest = ';02134,42.3126,-71.0553;10001,40.7506,-73.9972;99929,56.2215,-131.9236;';

			FindRadius.Center first = FindRadius.centroid('02134');
			FindRadius.Center last = FindRadius.centroid('99929');

			System.Assert.areEqual(42.3126, first.latitude, 'The first record.');
			System.Assert.areEqual(-131.9236, last.longitude, 'The last record.');
			System.Assert.isNull(FindRadius.centroid('1000'), 'A prefix is not a code.');
			System.Assert.isNull(FindRadius.centroid('02135'), 'Not in this table.');
		}
	}

	@IsTest
	static void theTypedPlaceIsAPostalCodeOrARecordAndNothingElse() {
		System.runAs(TestUsers.admin()) {
			for (String refused : new List<String>{ '', '  ', '00000', '1 Main Street, Boston' }) {
				try {
					FindRadius.resolveCenter(refused);
					System.Assert.fail('Refused: ' + refused);
				} catch (FindRadius.FindRadiusException expected) {
					System.Assert.isFalse(
						String.isBlank(expected.getMessage()),
						'The message says what to do: ' + refused
					);
				}
			}
			System.Assert.isNotNull(FindRadius.resolveCenter(' 02134 '), 'Spaces are ignored.');
		}
	}

	@IsTest
	static void aRecordsOwnGeocodeIsUsedElseItsPostalCodeStandsInElseItIsRefused() {
		System.runAs(TestUsers.admin()) {
			Contact geocoded = contact('Geocoded', 41.5, -72.5);
			Contact postalOnly = contact('PostalOnly', null, null);
			Contact neither = new Contact(LastName = 'Neither');
			insert new List<Contact>{ geocoded, postalOnly, neither };

			FindRadius.Center own = FindRadius.resolveCenter(geocoded.Id);
			FindRadius.Center stand = FindRadius.resolveCenter(postalOnly.Id);

			System.Assert.areEqual(41.5, own.latitude, 'Its own geocode.');
			System.Assert.isNull(own.note, 'No stand in.');
			System.Assert.isNotNull(stand.note, 'The stand in says so.');
			System.Assert.isTrue(
				stand.latitude > 42 && stand.latitude < 43,
				'The postal code center.'
			);
			try {
				FindRadius.resolveCenter(neither.Id);
				System.Assert.fail('No geocode and no postal code');
			} catch (FindRadius.FindRadiusException expected) {
				System.Assert.areEqual(
					BarnHelp.text('Core', 'Core_Find_RadiusNoGeocode'),
					expected.getMessage(),
					'The reason is given.'
				);
			}
		}
	}

	@IsTest
	static void theConditionIsCheckedAgainstTheDescribe() {
		System.runAs(TestUsers.admin()) {
			FindRelatedRecords.Rendered ok = FindRadius.condition(
				'Contact',
				JSON.deserializeUntyped(
					'{"field": "MailingAddress", "miles": 25, "latitude": 42.3, "longitude": -71.1}'
				)
			);

			System.Assert.isTrue(ok.clause.startsWith('DISTANCE(MailingAddress, GEOLOCATION(:'));
			System.Assert.areEqual(3, ok.binds.size(), 'Latitude, longitude and miles are binds.');
			System.Assert.isTrue(ok.display.contains('< 25'), ok.display);
			for (
				String bad : new List<String>{
					'{"field": "LastName", "miles": 5, "latitude": 1, "longitude": 1}',
					'{"field": "MailingAddress; DROP", "miles": 5, "latitude": 1, "longitude": 1}',
					'{"field": "MailingAddress", "miles": 0, "latitude": 1, "longitude": 1}',
					'{"field": "MailingAddress", "miles": 501, "latitude": 1, "longitude": 1}',
					'{"field": "MailingAddress", "miles": 2.5, "latitude": 1, "longitude": 1}',
					'{"field": "MailingAddress", "miles": 5, "latitude": 91, "longitude": 1}',
					'{"field": "MailingAddress", "miles": 5, "longitude": 1}',
					'{"field": "MailingAddress", "miles": "far", "latitude": 1, "longitude": 1}'
				}
			) {
				try {
					FindRadius.condition('Contact', JSON.deserializeUntyped(bad));
					System.Assert.fail('Refused: ' + bad);
				} catch (FindRadius.FindRadiusException expected) {
					System.Assert.isFalse(String.isBlank(expected.getMessage()), bad);
				}
			}
			try {
				FindRadius.condition('Contact', 'MailingAddress');
				System.Assert.fail('Not a map');
			} catch (FindRadius.FindRadiusException expected) {
				System.Assert.isFalse(String.isBlank(expected.getMessage()), 'Refused.');
			}
		}
	}

	@IsTest
	static void addressAndLocationFieldsAreOffered() {
		System.runAs(TestUsers.admin()) {
			Set<String> names = new Set<String>();
			for (FindRadius.FieldOption option : FindRadius.fieldOptions('Contact')) {
				names.add(option.value);
			}

			System.Assert.isTrue(names.contains('MailingAddress'), 'Mailing address.');
			System.Assert.isTrue(names.contains('OtherAddress'), 'Other address.');
			System.Assert.isFalse(names.contains('LastName'), 'Only places.');
			System.Assert.areEqual(
				'(MailingLatitude = NULL AND MailingPostalCode != NULL)',
				FindRadius.missingGeocodeClause('Contact', 'MailingAddress'),
				'Where a geocode should be and is not.'
			);
		}
	}

	@IsTest
	static void aQueryKeepsOnlyRecordsWithinTheDistanceAndCountsTheUngeocoded() {
		System.runAs(TestUsers.admin()) {
			insert new List<Contact>{
				contact('Near', 42.31, -71.05),
				contact('Far', 34.05, -118.24),
				contact('Ungeocoded', null, null),
				new Contact(LastName = 'NoAddress')
			};

			QueryCompiler.Compiled compiled = QueryCompiler.compile(document(25));
			List<SObject> rows = QueryCompiler.run(compiled);

			System.Assert.isTrue(
				compiled.display.contains('DISTANCE(MailingAddress'),
				compiled.display
			);
			System.Assert.areEqual(
				new List<String>{ 'Near' },
				lastNames(rows),
				'Only the record within 25 miles: the others are far, ungeocoded or have no address.'
			);
			System.Assert.areEqual(
				1,
				QueryCompiler.countWithoutGeocode(document(25), 100),
				'The record with a postal code and no geocode is counted; the one with no address is not.'
			);
			System.Assert.areEqual(
				0,
				QueryCompiler.countWithoutGeocode(
					'{"version": 1, "object": "Contact", "fields": ["LastName"]}',
					100
				),
				'No radius, nothing to explain.'
			);
		}
	}

	@IsTest
	static void aBadRadiusInTheDocumentIsRefusedWithTheReason() {
		System.runAs(TestUsers.admin()) {
			try {
				QueryCompiler.compile(document(0));
				System.Assert.fail('Zero miles');
			} catch (QueryCompiler.QueryCompilerException expected) {
				System.Assert.isTrue(expected.getMessage().contains('500'), expected.getMessage());
			}
			try {
				QueryCompiler.compile(
					'{"version": 1, "object": "Contact", "fields": ["LastName"], "radius": "near"}'
				);
				System.Assert.fail('Not an object');
			} catch (QueryCompiler.QueryCompilerException expected) {
				System.Assert.areEqual(
					BarnHelp.text('Core', 'Core_Find_ErrorInvalidQuery'),
					expected.getMessage(),
					'Unreadable.'
				);
			}
		}
	}

	@IsTest
	static void theFindControllerRunsAResolvesAndListsForAPermittedUser() {
		System.runAs(TestUsers.admin()) {
			insert new List<Contact>{
				contact('Near', 42.31, -71.05),
				contact('Ungeocoded', null, null)
			};
			User maria = TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });

			System.runAs(maria) {
				FindController.QueryResult result = FindController.runQuery(document(25));
				FindRadius.Center center = FindController.resolveRadiusCenter('02134');

				System.Assert.areEqual(1, result.rows.size(), 'The one near record.');
				System.Assert.areEqual(1, result.withoutGeocode, 'One cannot be placed.');
				System.Assert.isNotNull(center.latitude, 'A postal code resolves.');
				System.Assert.isFalse(
					FindController.listRadiusFields('Contact').isEmpty(),
					'Contact has address fields.'
				);
				try {
					FindController.resolveRadiusCenter('not a place');
					System.Assert.fail('Refused');
				} catch (AuraHandledException expected) {
					System.Assert.isTrue(
						expected.getMessage().contains('not a place'),
						'The person is shown the reason: ' + expected.getMessage()
					);
				}
			}
		}
	}
}
