/**
 * The off-Salesforce gift templates (MIG-07; admin guide "Moving From Another CRM"): each one is
 * copied into the org like every shipped template, reads as a mapping, and loads what a gift
 * import needs: the donor's email to find them by, the amount, the date and a fund.
 */
@IsTest(testFor='ApexClass:ImportTemplateService, ApexClass:ImportMapping')
private class CrmGiftTemplatesTest {
	private static final List<String> KEYS = new List<String>{
		'crm_donorperfect_gifts',
		'crm_bloomerang_gifts',
		'crm_lgl_gifts',
		'crm_neon_gifts',
		'crm_civicrm_gifts',
		'crm_re_nxt_gifts'
	};
	private static final Set<String> NEEDED = new Set<String>{
		'contact1.email',
		'contact1.lastname',
		'gift.amount__c',
		'gift.gift_date__c',
		'gift.external_id__c',
		'allocation.fund'
	};

	@IsTest
	static void eachTemplateIsCopiedAndMapsWhatAGiftNeeds() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			ImportTemplateService.materializeDefaults();
			Map<String, Import_Template__c> byKey = new Map<String, Import_Template__c>();
			for (Import_Template__c copied : [
				SELECT Template_Key__c, Column_Mapping_JSON__c, Matching_Rule__c
				FROM Import_Template__c
				WHERE Template_Key__c IN :KEYS
				WITH SYSTEM_MODE
			]) {
				byKey.put(copied.Template_Key__c, copied);
			}
			for (String key : KEYS) {
				Import_Template__c copied = byKey.get(key);
				Assert.isNotNull(copied, key + ' is copied into the org');
				Assert.areEqual(
					'Email exact',
					copied.Matching_Rule__c,
					key + ' finds donors by email'
				);
				Set<String> targets = new Set<String>();
				Set<String> sources = new Set<String>();
				for (
					ImportMapping.Column column : ImportMapping.parse(copied.Column_Mapping_JSON__c)
						.columns
				) {
					targets.add(column.target.toLowerCase());
					Assert.isTrue(sources.add(column.source), key + ' names each heading once');
				}
				Assert.isTrue(targets.containsAll(NEEDED), key + ' maps what a gift needs');
			}
		}
	}
}
