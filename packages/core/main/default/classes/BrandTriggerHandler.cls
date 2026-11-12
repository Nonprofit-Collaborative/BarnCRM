/**
 * The Brand, Legal Entity and Brand Assignment automation (C-47, canonical model R-BR1, R-BR7,
 * R-BR9), registered once per object. Before save it sets an assignment's key; after save it
 * keeps one default brand and entity and one primary assignment per record, and asks for share
 * upkeep while brand visibility is on.
 */
public with sharing class BrandTriggerHandler extends TriggerHandler {
	public override void beforeInsert() {
		prepare();
	}

	public override void beforeUpdate() {
		prepare();
	}

	public override void afterInsert() {
		afterSave(newRecords());
	}

	public override void afterUpdate() {
		List<SObject> touched = new List<SObject>(newRecords());
		touched.addAll(oldRecords());
		afterSave(touched);
	}

	public override void afterDelete() {
		requestShares(oldRecords());
	}

	public override void afterUndelete() {
		afterSave(newRecords());
	}

	private void prepare() {
		List<SObject> records = newRecords();
		if (!records.isEmpty() && records[0] instanceof Brand_Assignment__c) {
			BrandService.prepareAssignments((List<Brand_Assignment__c>) records);
		}
	}

	private void afterSave(List<SObject> touched) {
		List<SObject> records = newRecords();
		try {
			if (records[0] instanceof Brand_Assignment__c) {
				BrandService.keepOnePrimary((List<Brand_Assignment__c>) records);
			} else {
				BrandService.keepOneDefault(records);
			}
		} catch (Exception thrown) {
			reportFailure(
				thrown,
				records,
				'BrandTriggerHandler.afterSave',
				BarnHelp.text('Core', 'Core_Brand_SaveFailed')
			);
		}
		requestShares(touched);
	}

	private void requestShares(List<SObject> rows) {
		if (rows.isEmpty() || !BrandService.visibilityOn()) {
			return;
		}
		if (rows[0] instanceof Brand_Assignment__c) {
			BrandShareJob.request(rows);
		} else if (rows[0] instanceof Brand__c) {
			BrandShareJob.requestFull();
		}
	}
}
