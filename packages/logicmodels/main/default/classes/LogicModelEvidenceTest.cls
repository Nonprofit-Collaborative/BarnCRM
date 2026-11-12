/**
 * The evidence log (L-05, canonical model 29ZE1, R-AE1 to R-AE3): evidence added to an arrow's
 * assumption comes back with the model, newest first, with Moderate when no strength is given;
 * it can be changed and removed; removing the arrow removes its evidence; a reader sees it but
 * cannot add to it.
 */
@IsTest(testFor='ApexClass:LogicModelBuilderController, ApexClass:LogicModelService')
private class LogicModelEvidenceTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith('Logic_Models_Admin');
		TestUsers.standardUserWith(
			'Reader',
			new List<String>{ 'BarnCRM_Read_Only', 'Logic_Models_Read_Only' }
		);
	}

	private static Id newLink() {
		Logic_Model__c model = new Logic_Model__c(Name = 'Reading Program Model');
		insert as user model;
		List<Logic_Model_Element__c> parts = new List<Logic_Model_Element__c>{
			new Logic_Model_Element__c(
				Logic_Model__c = model.Id,
				Name = 'Sessions',
				Type__c = 'Activity'
			),
			new Logic_Model_Element__c(
				Logic_Model__c = model.Id,
				Name = 'Reads at home',
				Type__c = 'Outcome',
				Outcome_Term__c = 'Short Term'
			)
		};
		insert as user parts;
		Logic_Model_Link__c link = new Logic_Model_Link__c(
			Logic_Model__c = model.Id,
			From_Element__c = parts[0].Id,
			To_Element__c = parts[1].Id,
			Assumption__c = 'Families who come read more at home.'
		);
		insert as user link;
		return link.Id;
	}

	private static List<Object> evidenceIn(Map<String, Object> model) {
		Map<String, Object> link = (Map<String, Object>) ((List<Object>) model.get('links'))[0];
		return (List<Object>) link.get('evidence');
	}

	@IsTest
	static void evidenceIsAddedChangedAndRemovedWithItsArrow() {
		System.runAs(TestUsers.adminWith('Logic_Models_Admin')) {
			Id linkId = newLink();

			Test.startTest();
			LogicModelBuilderController.saveEvidence(
				JSON.serialize(
					new Map<String, Object>{
						'linkId' => linkId,
						'summary' => 'Staff saw more reading logs.',
						'source' => 'Staff observation'
					}
				)
			);
			Map<String, Object> model = LogicModelBuilderController.saveEvidence(
				JSON.serialize(
					new Map<String, Object>{
						'linkId' => linkId,
						'summary' => 'Twice as many books read.',
						'source' => '2025 parent survey',
						'sourceUrl' => 'https://example.org/survey',
						'date' => '2025-06-30',
						'strength' => 'Strong'
					}
				)
			);
			List<Object> evidence = evidenceIn(model);
			Map<String, Object> newest = (Map<String, Object>) evidence[0];
			Map<String, Object> undated = (Map<String, Object>) evidence[1];
			model = LogicModelBuilderController.saveEvidence(
				JSON.serialize(
					new Map<String, Object>{
						'id' => undated.get('id'),
						'summary' => 'Staff saw more reading logs.',
						'strength' => 'Limited'
					}
				)
			);
			Map<String, Object> changed = (Map<String, Object>) evidenceIn(model)[1];
			model = LogicModelBuilderController.remove((Id) newest.get('id'));
			Integer left = evidenceIn(model).size();
			LogicModelBuilderController.remove(linkId);
			Test.stopTest();

			Assert.areEqual(2, evidence.size(), 'Two pieces of evidence');
			Map<String, Object> words = (Map<String, Object>) model.get('evidenceText');
			Assert.areEqual(4, ((List<Object>) words.get('strengths')).size(), 'Four strengths');
			Assert.areEqual('Strong', newest.get('strength'), 'Dated evidence first');
			Assert.areEqual('Moderate', undated.get('strength'), 'Moderate when none is given');
			Assert.areEqual('Limited', changed.get('strength'), 'Changed');
			Assert.areEqual(1, left, 'One removed');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Assumption_Evidence__c WITH SYSTEM_MODE],
				'Removing the arrow removes its evidence'
			);
		}
	}

	@IsTest
	static void aReaderSeesEvidenceButCannotAddIt() {
		Id linkId;
		System.runAs(TestUsers.adminWith('Logic_Models_Admin')) {
			linkId = newLink();
			insert as user new Assumption_Evidence__c(Link__c = linkId, Summary__c = 'Seen.');
		}
		User reader = [SELECT Id FROM User WHERE LastName = 'Reader' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(reader) {
			Id modelId = [SELECT Logic_Model__c FROM Logic_Model_Link__c WITH SYSTEM_MODE]
			.Logic_Model__c;
			Test.startTest();
			Map<String, Object> model = LogicModelBuilderController.getModel(modelId);
			Boolean refused = false;
			try {
				LogicModelBuilderController.saveEvidence(
					JSON.serialize(
						new Map<String, Object>{ 'linkId' => linkId, 'summary' => 'No.' }
					)
				);
			} catch (AuraHandledException e) {
				refused = true;
			}
			Test.stopTest();

			Assert.areEqual(1, evidenceIn(model).size(), 'The reader sees the evidence');
			Assert.isTrue(refused, 'And cannot add any');
		}
	}
}
