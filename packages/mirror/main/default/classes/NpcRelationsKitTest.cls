/**
 * The Nonprofit Cloud Relationships and Affiliations kit (MIG-02, canonical model R-MK1): both
 * steps read as import steps whose shipped templates are copied into the org, load a Core
 * object and name only columns the step reads or the extension adds; a pair of people held both
 * ways round is copied once; an affiliation with a household or a person account is skipped and
 * its roles read as text. Nonprofit Cloud itself is not needed: the kit holds its names as data.
 */
@IsTest(testFor='ApexClass:NpcRelationsKit, ApexClass:MigrationKitService')
private class NpcRelationsKitTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	@IsTest
	static void eachStepHasItsTemplateAndNamesOnlyWhatItReads() {
		System.runAs(TestUsers.admin()) {
			Migration_Kit__mdt kit = MigrationKitService.kitNamed(NpcRelationsKit.KIT);
			ImportTemplateService.materializeDefaults();
			Map<String, String> targetByStep = new Map<String, String>{
				'relationships' => 'Relationship__c',
				'affiliations' => 'Affiliation__c'
			};
			for (String key : targetByStep.keySet()) {
				MigrationKitService.Step step = MigrationKitService.stepNamed(kit, key);
				Assert.areEqual(MigrationKitService.KIND_IMPORT, step.kind, key + ' loads');
				Import_Template__c template = [
					SELECT Column_Mapping_JSON__c, Target_Object__c
					FROM Import_Template__c
					WHERE Template_Key__c = :step.templateKey
					WITH SYSTEM_MODE
				];
				Assert.isTrue(
					template.Target_Object__c.endsWith(targetByStep.get(key)),
					key + ' loads ' + targetByStep.get(key)
				);
				for (
					ImportMapping.Column column : ImportMapping.parse(
							template.Column_Mapping_JSON__c
						)
						.getColumns()
				) {
					String heading = column.getSource();
					Assert.isTrue(
						step.fields.contains(heading) || heading == 'Role',
						key + ' maps only what it reads: ' + heading
					);
				}
				MigrationCheck check = new NpcRelationsKit().verify(key);
				Assert.areEqual(check.source, check.done, key + ': nothing to copy here');
			}
		}
	}

	@IsTest
	static void aPairHeldBothWaysIsCopiedOnce() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		String ana = '003000000000001AAA';
		String ben = '003000000000002AAA';
		String cara = '003000000000003AAA';
		List<Map<String, Object>> rows = new List<Map<String, Object>>{
			new Map<String, Object>{ 'ContactId' => ana, 'RelatedContactId' => ben },
			new Map<String, Object>{ 'ContactId' => ben, 'RelatedContactId' => ana },
			new Map<String, Object>{ 'ContactId' => cara, 'RelatedContactId' => ana }
		};
		List<Map<String, Object>> kept = NpcRelationsKit.oneSide(
			rows,
			new Set<String>{ ana + ben, ben + ana }
		);
		Assert.areEqual(2, kept.size(), 'Ana and Ben once, Cara and Ana once');
		Assert.areEqual(ana, kept[0].get('ContactId'), 'the side whose person sorts first');
		Assert.areEqual(cara, kept[1].get('ContactId'), 'held one way only');
	}

	@IsTest
	static void withoutNonprofitCloudTheStepsAreRefusedAndNothingIsWanted() {
		System.runAs(TestUsers.admin()) {
			NpcRelationsKit extension = new NpcRelationsKit();
			for (String key : new List<String>{ 'relationships', 'affiliations' }) {
				try {
					Assert.isNotNull(extension.rows(key, new List<SObject>()), key);
				} catch (Exception refused) {
					Assert.isTrue(
						refused.getMessage().contains('this org does not have'),
						key + ' names what is missing: ' + refused.getMessage()
					);
				}
				MigrationCheck check = extension.verify(key);
				Assert.areEqual(0, check.source, key + ': nothing to copy');
				Assert.areEqual(0, check.done, key + ': nothing copied');
			}
		}
	}

	@IsTest
	static void stepRowsAreShapedWhenNonprofitCloudHoldsNoOtherDirectionOrHousehold() {
		System.runAs(TestUsers.admin()) {
			List<Map<String, Object>> relationships = NpcRelationsKit.shape(
				'relationships',
				new List<Map<String, Object>>{
					new Map<String, Object>{ 'ContactId' => '', 'RelatedContactId' => '' }
				}
			);
			Assert.areEqual(1, relationships.size(), 'no reverse side to drop');
			List<Map<String, Object>> affiliations = NpcRelationsKit.shape(
				'affiliations',
				new List<Map<String, Object>>{
					new Map<String, Object>{
						'AccountId' => '001000000000004AAA',
						'Roles' => 'Donor;Advisor'
					}
				}
			);
			Assert.areEqual(1, affiliations.size(), 'an organization is kept');
			Assert.areEqual('Donor, Advisor', affiliations[0].get('Role'), 'roles as text');
			Assert.isTrue(
				NpcRelationsKit.notOrganizations(new Set<String>()).isEmpty(),
				'no accounts to check'
			);
			Assert.areEqual(
				new Set<String>{ 'x' },
				NpcRelationsKit.column(
					new List<Map<String, Object>>{
						new Map<String, Object>{ 'AccountId' => 'x' },
						new Map<String, Object>{ 'AccountId' => ' ' }
					},
					'AccountId'
				),
				'distinct non-blank values'
			);
		}
	}

	@IsTest
	static void barnRecordsAloneAreNotCountedAsCopiedAndReadsAreBoundedByTheObject() {
		System.runAs(TestUsers.admin()) {
			Account org = TestDataFactory.organization(new Account(Name = 'Relkit Org'));
			insert org;
			List<Contact> people = new List<Contact>{
				TestDataFactory.person(new Contact(LastName = 'Relkit One')),
				TestDataFactory.person(new Contact(LastName = 'Relkit Two'))
			};
			insert people;
			insert new Relationship__c(
				Contact__c = people[0].Id,
				Related_Contact__c = people[1].Id,
				Type__c = 'Friend',
				Status__c = 'Current'
			);
			insert new Affiliation__c(
				Contact__c = people[0].Id,
				Organization__c = org.Id,
				Role__c = 'Volunteer',
				Status__c = 'Current'
			);
			for (String key : new List<String>{ 'relationships', 'affiliations' }) {
				MigrationCheck check = new NpcRelationsKit().verify(key);
				Assert.areEqual(0, check.source, key + ': nothing in Nonprofit Cloud to copy');
				Assert.areEqual(0, check.done, key + ': BarnCRM records alone are not copies');
			}
			Assert.areEqual(
				2,
				NpcRelationsKit.read(
						'SELECT Id FROM Contact WHERE Id IN :ids',
						new Set<String>{ people[0].Id, people[1].Id }
					)
					.size(),
				'a present object is read'
			);
			Assert.isTrue(
				NpcRelationsKit.read(
						'SELECT Id FROM NoSuchObject__x WHERE Id IN :ids',
						new Set<String>{ people[0].Id }
					)
					.isEmpty(),
				'an absent object reads as none'
			);
		}
	}

	@IsTest
	static void aPairHeldOneWayOnlyKeepsEveryRowAndBlankRolesStayBlank() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		List<Map<String, Object>> rows = new List<Map<String, Object>>{
			new Map<String, Object>{
				'ContactId' => '003000000000002AAA',
				'RelatedContactId' => '003000000000001AAA'
			}
		};
		Assert.areEqual(1, NpcRelationsKit.oneSide(rows, new Set<String>()).size(), 'one way');
		List<Map<String, Object>> kept = NpcRelationsKit.organizations(
			new List<Map<String, Object>>{
				new Map<String, Object>{ 'AccountId' => '001000000000003AAA', 'Roles' => '' }
			},
			new Set<String>()
		);
		Assert.areEqual('', kept[0].get('Role'), 'no roles');
	}

	@IsTest
	static void anAffiliationWithAHouseholdIsSkipped() {
		// runs-as: deploying user (text rows only, no record or permission is read)
		List<Map<String, Object>> rows = new List<Map<String, Object>>{
			new Map<String, Object>{
				'AccountId' => '001000000000001AAA',
				'Roles' => 'Employee;Board Member'
			},
			new Map<String, Object>{ 'AccountId' => '001000000000002AAA', 'Roles' => null }
		};
		List<Map<String, Object>> kept = NpcRelationsKit.organizations(
			rows,
			new Set<String>{ '001000000000002AAA' }
		);
		Assert.areEqual(1, kept.size(), 'the household is skipped');
		Assert.areEqual('Employee, Board Member', kept[0].get('Role'), 'roles as text');
	}
}
