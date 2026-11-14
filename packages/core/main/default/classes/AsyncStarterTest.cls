/**
 * The one async starter (D-200 P9): it starts work when there is room, and when the org is
 * busy it refuses with a message for the person, logged once.
 */
@IsTest(testFor='ApexClass:AsyncStarter, ApexClass:ErrorLogger')
private class AsyncStarterTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private class NothingQueued implements Queueable {
		public void execute(QueueableContext context) {
			return;
		}
	}

	@IsTest
	static void withRoomTheWorkStarts() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			Id batchId = AsyncStarter.batch(new AsyncStarterTestBatch(), 200, 'AsyncStarterTest');
			Id queuedId = AsyncStarter.queue(new NothingQueued(), 'AsyncStarterTest');
			Test.stopTest();

			Assert.isNotNull(batchId, 'The batch started');
			Assert.isNotNull(queuedId, 'The job was queued');
		}
	}

	@IsTest
	static void whenBusyThePersonIsToldAndItIsLoggedOnce() {
		System.runAs(TestUsers.admin()) {
			AsyncStarter.busyForTest = true;
			String message;

			Test.startTest();
			try {
				AsyncStarter.batch(new AsyncStarterTestBatch(), 200, 'AsyncStarterTest');
			} catch (AsyncStarter.BusyException busy) {
				message = busy.getMessage();
				// A caller that logs what it catches does not log the refusal again.
				ErrorLogger.log(busy, 'AsyncStarterTest');
			}
			Boolean queueRefused = false;
			try {
				AsyncStarter.queue(new NothingQueued(), 1, 'AsyncStarterTest');
			} catch (AsyncStarter.BusyException busy) {
				queueRefused = true;
			}
			Test.stopTest();

			Assert.areEqual(BarnHelp.text('Core', 'Core_AsyncStarter_Busy'), message);
			Assert.isTrue(queueRefused, 'A queued job is refused too');
			// The two refusals read the same way, so they are counted on one entry (R-E7).
			Decimal refusals = (Decimal) [
					SELECT SUM(Occurrences__c) total
					FROM Error_Log__c
					WHERE Context__c = 'AsyncStarterTest'
				][0]
				.get('total');
			Assert.areEqual(
				2,
				refusals.intValue(),
				'One count per refusal, none for the caller logging it again'
			);
		}
	}

	/**
	 * A start Salesforce never allows, such as a batch from a batch execute or a future method,
	 * is a fault in the code: it is not reported as a busy org, and its real message is logged
	 * as an Error. A refusal for want of room is still busy.
	 */
	@IsTest
	static void aRefusalThatIsNotABusyOrgKeepsItsRealMessage() {
		System.runAs(TestUsers.admin()) {
			String notAllowed =
				'Database.executeBatch cannot be called from a batch start, batch execute, ' +
				'or future method.';
			AsyncStarter.refusalForTest = new AsyncException(notAllowed);
			Exception batchThrown;
			Exception queueThrown;
			Exception capacityThrown;

			Test.startTest();
			try {
				AsyncStarter.batch(new AsyncStarterTestBatch(), 200, 'AsyncStarterFault');
			} catch (Exception thrown) {
				batchThrown = thrown;
			}
			try {
				AsyncStarter.queue(new NothingQueued(), 'AsyncStarterFault');
			} catch (Exception thrown) {
				queueThrown = thrown;
			}
			AsyncStarter.refusalForTest = new AsyncException(
				'You have exceeded the limit of 100 jobs in the flex queue.'
			);
			try {
				AsyncStarter.batch(new AsyncStarterTestBatch(), 200, 'AsyncStarterFull');
			} catch (Exception thrown) {
				capacityThrown = thrown;
			}
			Test.stopTest();

			Assert.isInstanceOfType(batchThrown, AsyncException.class, 'Rethrown as it is');
			Assert.areEqual(notAllowed, batchThrown.getMessage(), 'With its real message');
			Assert.isInstanceOfType(queueThrown, AsyncException.class, 'A queued job too');
			Assert.isInstanceOfType(
				capacityThrown,
				AsyncStarter.BusyException.class,
				'A full queue is still a busy org'
			);
			List<Error_Log__c> logged = [
				SELECT Message__c, Severity__c
				FROM Error_Log__c
				WHERE Context__c = 'AsyncStarterFault'
				WITH SYSTEM_MODE
			];
			Assert.isFalse(logged.isEmpty(), 'The fault is logged');
			Assert.areEqual(ErrorLogger.SEVERITY_ERROR, logged[0].Severity__c, 'As an Error');
			Assert.areEqual(notAllowed, logged[0].Message__c, 'With the real message');
		}
	}
}
