/**
 * Extra fields the Opportunity mirror copies through a saved map (MAP-07, canonical model
 * R-OM12): a gift field with steps and a fixed value are copied, a field R-OM3 writes is never
 * replaced, a change to a field the map reads copies again, and a name that finds no usable map
 * copies nothing extra.
 *
 * Opportunity is read only through dynamic queries, so this class compiles where Opportunity does
 * not exist; there each test stops once it has checked that the map reads as empty.
 */
@IsTest(
	testFor='ApexClass:OpportunityMirrorMap, ApexClass:OpportunityMirrorContext, ApexClass:GivingWhereUsedExtension'
)
private class OpportunityMirrorMapTest {
	private static final String MAP_NAME = 'Gift extras';

	@TestSetup
	static void setup() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.ensureDefaultFund();
			GivingTestDataFactory.insertHouseholdContact('The Garcia Household', 'Luis', 'Garcia');
			Saved_Transform__c chosen = new Saved_Transform__c(
				Name = MAP_NAME,
				Kind__c = 'Map',
				Object_Name__c = 'Opportunity',
				Definition_JSON__c = JSON.serialize(
					new Map<String, Object>{
						'version' => 4,
						'from' => new Map<String, Object>{ 'kind' => 'record', 'object' => 'Gift__c' },
						'to' => new Map<String, Object>{ 'kind' => 'record', 'object' => 'Opportunity' },
						'columns' => new List<Object>{
							new Map<String, Object>{
								'source' => 'Payment_Reference__c',
								'target' => 'Record.Description',
								'transforms' => new List<Object>{ new Map<String, Object>{ 'op' => 'upper' } }
							},
							new Map<String, Object>{ 'value' => 'Mirrored', 'target' => 'Record.NextStep' },
							new Map<String, Object>{ 'value' => '1', 'target' => 'Record.Amount' }
						},
						'defaults' => new List<Object>{
							new Map<String, Object>{ 'target' => 'Record.Description', 'value' => 'none' }
						}
					}
				)
			);
			insert chosen;
			Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
			settings.Opportunity_Mirror_Direction__c = OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES;
			settings.Opportunity_Mirror_Map__c = chosen.Id;
			upsert settings;
		}
	}

	private static Gift__c gift(String reference) {
		Contact luis = [SELECT Id FROM Contact WHERE LastName = 'Garcia' LIMIT 1];
		Gift__c gift = GivingTestDataFactory.buildGift(luis.Id, 25);
		gift.Gift_Date__c = Date.newInstance(2026, 9, 20);
		gift.Payment_Reference__c = reference;
		return gift;
	}

	private static SObject opportunityOf(Id giftId) {
		Gift__c saved = [SELECT Opportunity_Id__c FROM Gift__c WHERE Id = :giftId];
		Id opportunityId = saved.Opportunity_Id__c;
		return Database.queryWithBinds(
			'SELECT Amount, Description, NextStep FROM ' +
				OpportunityMirrorService.opportunityType().getDescribe().getName() +
				' WHERE Id = :opportunityId',
			new Map<String, Object>{ 'opportunityId' => opportunityId },
			AccessLevel.SYSTEM_MODE
		)[0];
	}

	@IsTest
	static void copiesTheMapsFieldsWithStepsAndNeverReplacesTheMirrorsOwn() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			if (OpportunityMirrorService.opportunityType() == null) {
				System.Assert.isTrue(OpportunityMirrorMap.current().targetFields().isEmpty(), 'Nothing to copy to');
				return;
			}
			System.Assert.areEqual(
				new List<String>{ 'Description', 'NextStep' },
				OpportunityMirrorMap.current().targetFields(),
				'Amount stays the mirror own field'
			);
			Gift__c saved = gift('chk-101');
			insert saved;

			SObject opportunity = opportunityOf(saved.Id);
			System.Assert.areEqual('CHK-101', opportunity.get('Description'), 'From the gift, with its step');
			System.Assert.areEqual('Mirrored', opportunity.get('NextStep'), 'A fixed value');
			System.Assert.areEqual(25, ((Decimal) opportunity.get('Amount')).intValue(), 'Never replaced');

			saved.Payment_Reference__c = null;
			update saved;
			System.Assert.areEqual(
				'none',
				opportunityOf(saved.Id).get('Description'),
				'A change to a field the map reads copies again, with When Blank, Use'
			);
		}
	}

	@IsTest
	static void whereUsedListsTheSettingBeforeTheMapIsChanged() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Saved_Transform__c row = [SELECT Id, Name FROM Saved_Transform__c LIMIT 1];
			System.Assert.isFalse(WhereUsedService.mapUsers(row.Id, row.Name).isEmpty(), 'The mirror links it');
			System.Assert.isFalse(
				WhereUsedService.mapUsers(row.Id, 'Renamed').isEmpty(),
				'By its record ID, so a new name keeps the link'
			);
			System.Assert.isTrue(OpportunityMirrorMap.links(MAP_NAME, row.Id, MAP_NAME), 'A value stored as a name');
			System.Assert.isFalse(OpportunityMirrorMap.links(MAP_NAME, row.Id, 'Another map'));
			System.Assert.isFalse(OpportunityMirrorMap.links(UserInfo.getUserId(), row.Id, MAP_NAME));
			System.Assert.isFalse(OpportunityMirrorMap.links('', row.Id, MAP_NAME));
		}
	}

	@IsTest
	static void aNameWithoutAUsableMapCopiesNothingExtra() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			System.Assert.isTrue(
				new OpportunityMirrorMap('No such map').targetFields().isEmpty(),
				'No map by that name'
			);
			Saved_Transform__c row = [SELECT Id, Definition_JSON__c FROM Saved_Transform__c LIMIT 1];
			if (OpportunityMirrorService.opportunityType() != null) {
				System.Assert.isFalse(new OpportunityMirrorMap(MAP_NAME).targetFields().isEmpty(), 'Read by name');
				System.Assert.isFalse(new OpportunityMirrorMap(row.Id).targetFields().isEmpty(), 'Read by ID');
			}
			row.Definition_JSON__c = row.Definition_JSON__c.replace('"Gift__c"', '"Account"');
			update row;
			System.Assert.isTrue(
				new OpportunityMirrorMap(MAP_NAME).targetFields().isEmpty(),
				'A map from another kind of record'
			);
			System.Assert.isTrue(
				new OpportunityMirrorMap(MAP_NAME).sourceFieldsBesides(OpportunityMirrorSelector.GIFT_FIELDS).isEmpty(),
				'Reads no gift field'
			);
		}
	}
}
