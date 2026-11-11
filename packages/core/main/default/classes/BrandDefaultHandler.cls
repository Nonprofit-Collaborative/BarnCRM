/**
 * Fills a blank Brand on new records of any object that has a `Brand__c` lookup (C-47d, R-BR4).
 * A module registers this Core class in its own Automation Registry row for its object, so
 * Core names no module object and the module ships no Apex for it. The parent whose brand is
 * copied is found by describe: the first custom lookup, in field name order, to an object that
 * itself has a Brand (an appeal for a gift). Does nothing while brands are off.
 */
public with sharing class BrandDefaultHandler extends TriggerHandler {
	public override void beforeInsert() {
		List<SObject> records = newRecords();
		if (records.isEmpty() || !BrandService.isEnabled()) {
			return;
		}
		try {
			BrandService.applyDefaults(records, parentField(records[0].getSObjectType()));
		} catch (Exception thrown) {
			reportFailure(
				thrown,
				records,
				'BrandDefaultHandler.beforeInsert',
				BarnHelp.text('Core', 'Core_Brand_SaveFailed')
			);
		}
	}

	@TestVisible
	private static String parentField(Schema.SObjectType type) {
		Map<String, Schema.SObjectField> fields = type.getDescribe().fields.getMap();
		List<String> names = new List<String>(fields.keySet());
		names.sort();
		for (String name : names) {
			Schema.DescribeFieldResult field = fields.get(name).getDescribe();
			if (
				field.isCustom() &&
				field.getType() == Schema.DisplayType.REFERENCE &&
				name != BrandService.BRAND_FIELD.toLowerCase() &&
				field.getReferenceTo().size() == 1 &&
				field.getReferenceTo()[0]
					.getDescribe()
					.fields.getMap()
					.containsKey(BrandService.BRAND_FIELD.toLowerCase())
			) {
				return field.getName();
			}
		}
		return null;
	}
}
