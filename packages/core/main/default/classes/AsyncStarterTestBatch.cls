/**
 * A batch that does nothing, for AsyncStarterTest: Apex lets only a top-level class implement
 * Database.Batchable.
 */
@IsTest
public class AsyncStarterTestBatch implements Database.Batchable<SObject> {
	public Database.QueryLocator start(Database.BatchableContext context) {
		return Database.getQueryLocator([SELECT Id FROM User WHERE Id = NULL WITH SYSTEM_MODE]);
	}

	public void execute(Database.BatchableContext context, List<SObject> scope) {
		return;
	}

	public void finish(Database.BatchableContext context) {
		return;
	}
}
