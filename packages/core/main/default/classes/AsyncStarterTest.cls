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
			Assert.areEqual(
				2,
				[SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'AsyncStarterTest'],
				'One entry per refusal, none for the caller logging it again'
			);
		}
	}
}
