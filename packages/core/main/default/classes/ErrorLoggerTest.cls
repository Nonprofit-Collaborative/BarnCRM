/**
 * What Maria reads when something fails, and the promise that logging never makes things worse.
 *
 * The two bulkification tests read `Limits.getPublishImmediateDML()`, not `Limits.getDmlStatements()`.
 * `ErrorLogWriter` records a failure by publishing an `Error_Log_Event__e` whose publish behavior is
 * Publish Immediately, and the platform meters those publishes on their own counter rather than on
 * the DML statement counter, which stays at zero on this path. The invariant being asserted is
 * unchanged: however many failures go in, one call goes out.
 */
@IsTest(testFor='ApexClass:ErrorLogger')
private class ErrorLoggerTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private class SampleException extends Exception {
	}

	private static Exception thrownException() {
		try {
			throw new SampleException('The pattern refers to a field this record does not have.');
		} catch (Exception caught) {
			return caught;
		}
	}

	@IsTest
	static void anExceptionBecomesSomethingMariaCanRead() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			ErrorLogger.log(thrownException(), 'Household naming');
			Test.stopTest();

			List<Error_Log__c> logged = [
				SELECT
					Context__c,
					Message__c,
					Technical_Detail__c,
					Severity__c,
					Status__c,
					Timestamp__c,
					User__c,
					Record_Reference__c,
					Object_Name__c
				FROM Error_Log__c
			];
			Assert.areEqual(1, logged.size(), 'One failure, one entry.');
			Error_Log__c entry = logged[0];
			Assert.areEqual('Household naming', entry.Context__c, 'Named in words, not in code.');
			Assert.areEqual(
				ErrorLogger.friendlyMessage('Household naming'),
				entry.Message__c,
				'What Maria reads is the plain language explanation, with no developer text in it.'
			);
			Assert.isTrue(
				entry.Message__c.contains('Household naming'),
				'And it names where it happened, so entries from different places differ.'
			);
			Assert.areEqual(
				BarnHelp.text('Core', 'Core_ErrorLog_UnexpectedFailure'),
				ErrorLogger.friendlyMessage(' '),
				'With nowhere to name, the plain explanation stands alone.'
			);
			Assert.isTrue(
				entry.Technical_Detail__c.contains('SampleException'),
				'The technical detail names the exception type.'
			);
			Assert.isTrue(
				entry.Technical_Detail__c.contains('The pattern refers to a field'),
				'And carries the words the exception itself used.'
			);
			Assert.areEqual(
				ErrorLogger.SEVERITY_ERROR,
				entry.Severity__c,
				'Severity defaults to Error.'
			);
			Assert.areEqual(ErrorLogger.STATUS_NEW, entry.Status__c, 'And status to New.');
			Assert.areEqual(UserInfo.getUserId(), entry.User__c, 'The person working is recorded.');
			Assert.isNotNull(entry.Timestamp__c, 'So is the time.');
			Assert.isNull(entry.Record_Reference__c, 'No record was named for this one.');
			Assert.isNull(entry.Object_Name__c, 'So there is nothing to group it by.');
		}
	}

	@IsTest
	static void anExceptionAboutARecordPointsAtThatRecord() {
		System.runAs(TestUsers.admin()) {
			Error_Log__c existing = TestDataFactory.insertErrorLogs(
				1,
				ErrorLogger.STATUS_RESOLVED
			)[0];

			Test.startTest();
			ErrorLogger.log(thrownException(), 'Household naming', existing.Id);
			Test.stopTest();

			List<Error_Log__c> logged = [
				SELECT Record_Reference__c, Object_Name__c
				FROM Error_Log__c
				WHERE Context__c = 'Household naming'
			];
			Assert.areEqual(1, logged.size(), 'One entry for the failure.');
			Assert.areEqual(
				String.valueOf(existing.Id),
				logged[0].Record_Reference__c,
				'Maria can open the record from the entry.'
			);
			Assert.areEqual(
				'Error_Log__c',
				logged[0].Object_Name__c,
				'And can group entries by what they affect.'
			);
		}
	}

	@IsTest
	static void twoHundredFailuresCostOneStatement() {
		System.runAs(TestUsers.admin()) {
			List<String> messages = new List<String>();
			for (Integer i = 0; i < 200; i++) {
				messages.add('Row ' + i + ' could not be saved because its household is missing.');
			}

			Test.startTest();
			Integer statementsBefore = Limits.getPublishImmediateDML();
			ErrorLogger.logMessages(messages, 'Spreadsheet import', ErrorLogger.SEVERITY_WARNING);
			Integer statementsAfter = Limits.getPublishImmediateDML();
			Test.stopTest();

			Assert.areEqual(
				1,
				statementsAfter - statementsBefore,
				'Logging is done in one statement.'
			);
			Assert.areEqual(
				200,
				[SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Warning'],
				'Every row that failed is recorded.'
			);
		}
	}

	@IsTest
	static void twoHundredMessagesAboutTheirOwnRecordsCostOneStatement() {
		System.runAs(TestUsers.admin()) {
			Id aboutMe = UserInfo.getUserId();
			List<String> messages = new List<String>();
			List<Id> recordIds = new List<Id>();
			for (Integer i = 0; i < 200; i++) {
				messages.add('Appeal ' + i + ' could not be copied.');
				recordIds.add(Math.mod(i, 2) == 0 ? aboutMe : null);
			}
			messages.add('A message with no record beside it.');
			messages.add('  ');

			Test.startTest();
			Integer statementsBefore = Limits.getPublishImmediateDML();
			ErrorLogger.logMessages(
				messages,
				recordIds,
				'Appeal copy',
				ErrorLogger.SEVERITY_WARNING
			);
			Integer statementsAfter = Limits.getPublishImmediateDML();
			Test.stopTest();

			Assert.areEqual(
				1,
				statementsAfter - statementsBefore,
				'Logging is done in one statement.'
			);
			Assert.areEqual(
				201,
				[SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Warning'],
				'Every message is recorded, and a blank one is not.'
			);
			Assert.areEqual(
				100,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Record_Reference__c = :String.valueOf(aboutMe)
				],
				'Each entry names its own record, and one given none names none.'
			);
		}
	}

	@IsTest
	static void aListOfExceptionsIsLoggedTogether() {
		System.runAs(TestUsers.admin()) {
			List<Exception> failures = new List<Exception>{
				thrownException(),
				null,
				thrownException()
			};

			Test.startTest();
			Integer statementsBefore = Limits.getPublishImmediateDML();
			ErrorLogger.log(failures, 'Spreadsheet import');
			Integer statementsAfter = Limits.getPublishImmediateDML();
			Test.stopTest();

			Assert.areEqual(1, statementsAfter - statementsBefore, 'Still one statement.');
			List<Error_Log__c> written = [SELECT Occurrences__c FROM Error_Log__c];
			Assert.areEqual(1, written.size(), 'The same failure twice is one entry (R-E7).');
			Assert.areEqual(2, written[0].Occurrences__c, 'The empty entry is skipped.');
		}
	}

	@IsTest
	static void aSeverityThatIsNotOfferedBecomesError() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			ErrorLogger.logMessage('The fund on this gift no longer exists.', null, 'Catastrophic');
			ErrorLogger.logMessage(
				'Nothing to worry about.',
				'Health check',
				ErrorLogger.SEVERITY_INFO
			);
			Test.stopTest();

			Assert.areEqual(
				1,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE Severity__c = 'Error' AND Context__c = 'BarnCRM'
				],
				'An unrecognized severity is recorded as an error, under a default context.'
			);
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'Info'],
				'An offered severity is kept.'
			);
		}
	}

	@IsTest
	static void loggingNothingRecordsNothingAndThrowsNothing() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			ErrorLogger.log((Exception) null, 'Household naming');
			ErrorLogger.log((List<Exception>) null, 'Household naming');
			ErrorLogger.log(new List<Exception>(), 'Household naming');
			ErrorLogger.logMessage('   ', 'Household naming', ErrorLogger.SEVERITY_ERROR);
			ErrorLogger.logMessages(null, 'Household naming', ErrorLogger.SEVERITY_ERROR);
			ErrorLogger.logMessages(new List<String>{ '  ' }, 'Import', ErrorLogger.SEVERITY_ERROR);
			Test.stopTest();

			Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'There was nothing to record.');
		}
	}

	@IsTest
	static void aVeryLongMessageIsTrimmedRatherThanLost() {
		System.runAs(TestUsers.admin()) {
			String enormous = 'x'.repeat(40000);

			Test.startTest();
			ErrorLogger.logMessage(enormous, enormous, ErrorLogger.SEVERITY_CRITICAL);
			Test.stopTest();

			List<Error_Log__c> logged = [SELECT Message__c, Context__c FROM Error_Log__c];
			Assert.areEqual(1, logged.size(), 'The entry was still written.');
			Assert.areEqual(32000, logged[0].Message__c.length(), 'The message is trimmed to fit.');
			Assert.areEqual(255, logged[0].Context__c.length(), 'So is the context.');
		}
	}

	@IsTest
	static void anEntrySurvivesTheRollbackItDocuments() {
		System.runAs(TestUsers.admin()) {
			// The failure this feature exists for ends in a rollback. An ordinary insert would be
			// undone with everything else, so the entry is published as a platform event instead
			// (canonical model rule R-E4). The person who hits the failure is David doing the day job,
			// whose access comes from the packaged permission set and not from a system administrator
			// profile, so the log runs inside System.runAs him: publishing is governed by Create on
			// the event, and if BarnCRM Staff did not carry it the writer would silently fall back
			// to the direct insert and the entry would go down with the rollback.
			User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });

			Test.startTest();
			Savepoint beforeTheFailure = Database.setSavepoint();
			TestDataFactory.insertErrorLogs(1, ErrorLogger.STATUS_NEW);
			System.runAs(david) {
				ErrorLogger.logMessage(
					'The household could not be renamed, so nothing was saved.',
					'Rollback',
					ErrorLogger.SEVERITY_ERROR
				);
			}
			Database.rollback(beforeTheFailure);
			Test.getEventBus().deliver();
			Test.stopTest();

			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Error_Log__c WHERE Context__c LIKE 'Test context%'],
				'The rollback undid the ordinary record, as a rollback does.'
			);
			List<Error_Log__c> survived = [
				SELECT Message__c, Severity__c, Status__c, User__c, Timestamp__c
				FROM Error_Log__c
				WHERE Context__c = 'Rollback'
			];
			Assert.areEqual(1, survived.size(), 'And the Error Log entry outlived it.');
			Assert.areEqual(
				'The household could not be renamed, so nothing was saved.',
				survived[0].Message__c,
				'With the message intact.'
			);
			Assert.areEqual(
				ErrorLogger.SEVERITY_ERROR,
				survived[0].Severity__c,
				'And its severity.'
			);
			Assert.areEqual(ErrorLogger.STATUS_NEW, survived[0].Status__c, 'Waiting to be read.');
			Assert.areEqual(david.Id, survived[0].User__c, 'Naming David, who was working.');
			Assert.isNotNull(survived[0].Timestamp__c, 'And when.');
		}
	}

	@IsTest
	static void anEventWithASeverityNobodyRecognizesIsStillWritten() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			ErrorLogEventHandler.handle(
				new List<Error_Log_Event__e>{
					new Error_Log_Event__e(
						Message__c = 'Something happened.',
						Context__c = 'Subscriber',
						Severity__c = 'Catastrophic'
					)
				}
			);
			ErrorLogEventHandler.handle(new List<Error_Log_Event__e>());
			ErrorLogEventHandler.handle(null);
			Test.stopTest();

			List<Error_Log__c> written = [SELECT Severity__c, Timestamp__c FROM Error_Log__c];
			Assert.areEqual(1, written.size(), 'The entry is written whatever the severity says.');
			Assert.areEqual(ErrorLogger.SEVERITY_ERROR, written[0].Severity__c, 'As an error.');
			Assert.isNotNull(written[0].Timestamp__c, 'With a time on it.');
		}
	}

	@IsTest
	static void anEntryNamesThePublisherNotTheUserThePayloadClaims() {
		System.runAs(TestUsers.admin()) {
			User someoneElse = TestUsers.minimumAccessUserWith(
				'Okafor',
				new List<String>{ 'BarnCRM_Read_Only' }
			);
			Error_Log_Event__e forged = (Error_Log_Event__e) JSON.deserialize(
				JSON.serialize(
					new Map<String, Object>{
						'attributes' => new Map<String, Object>{ 'type' => 'Error_Log_Event__e' },
						'CreatedById' => UserInfo.getUserId(),
						'User_Id__c' => someoneElse.Id,
						'Message__c' => 'Blamed on someone else.',
						'Context__c' => 'Forged'
					}
				),
				Error_Log_Event__e.class
			);

			Test.startTest();
			ErrorLogEventHandler.handle(new List<Error_Log_Event__e>{ forged });
			Test.stopTest();

			Error_Log__c written = [
				SELECT User__c
				FROM Error_Log__c
				WHERE Context__c = 'Forged'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(
				UserInfo.getUserId(),
				written.User__c,
				'The entry names whoever published the event, not the user its payload names.'
			);
		}
	}

	@IsTest
	static void theFallbackWritesEvenForSomeoneWithNoAccessToTheErrorLog() {
		System.runAs(TestUsers.admin()) {
			// The documented reason ErrorLogWriter is without sharing and writes in system mode: a
			// person who hits a failure because of their own access must still leave a trace.
			User david = TestDataFactory.createUser('David', new List<String>());

			Test.startTest();
			System.runAs(david) {
				ErrorLogWriter.writeDirectly(
					new List<Error_Log__c>{
						new Error_Log__c(
							Timestamp__c = System.now(),
							Context__c = 'No access',
							Message__c = 'Recorded for a user who cannot create Error Log records.',
							Severity__c = ErrorLogger.SEVERITY_ERROR,
							Status__c = ErrorLogger.STATUS_NEW
						)
					}
				);
				ErrorLogWriter.writeDirectly(new List<Error_Log__c>());
				ErrorLogWriter.writeDirectly(null);
			}
			Test.stopTest();

			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'No access'],
				'The entry is there even though the running user has no create access.'
			);
		}
	}

	@IsTest
	static void theTileCountsNewErrorsAndShowsTheMostRecent() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.insertErrorLogs(7, ErrorLogger.STATUS_NEW);
			TestDataFactory.insertErrorLogs(2, ErrorLogger.STATUS_RESOLVED);

			Test.startTest();
			Integer newCount = ErrorLogCountSelector.countNewUpTo(1000);
			List<Error_Log__c> recent = ErrorLogSelector.selectRecent(5);
			List<Error_Log__c> defaulted = ErrorLogSelector.selectRecent(null);
			List<Error_Log__c> capped = ErrorLogSelector.selectRecent(-3);
			Test.stopTest();

			Assert.areEqual(7, newCount, 'Only the new ones are counted.');
			Assert.areEqual(5, recent.size(), 'The tile shows five.');
			Assert.areEqual(5, defaulted.size(), 'Asking for none also shows five.');
			Assert.areEqual(5, capped.size(), 'So does asking for a nonsense number.');
			Assert.isTrue(
				recent[0].Timestamp__c >= recent[4].Timestamp__c,
				'The most recent is first.'
			);
		}
	}

	@IsTest
	static void anEntryCanBeReadBackById() {
		System.runAs(TestUsers.admin()) {
			List<Error_Log__c> existing = TestDataFactory.insertErrorLogs(
				2,
				ErrorLogger.STATUS_NEW
			);

			List<Error_Log__c> found = ErrorLogSelector.selectByIds(
				new Set<Id>{ existing[0].Id, existing[1].Id }
			);

			Assert.areEqual(2, found.size(), 'Both entries come back.');
			Assert.areEqual(
				0,
				ErrorLogSelector.selectByIds(new Set<Id>()).size(),
				'Asking for nothing queries nothing.'
			);
			Assert.areEqual(
				0,
				ErrorLogSelector.selectByIds(null).size(),
				'Asking for null queries nothing.'
			);
		}
	}

	private static Database.SaveResult saveResult(Boolean success, String message) {
		Map<String, Object> result = new Map<String, Object>{ 'success' => success };
		if (!success) {
			result.put(
				'errors',
				new List<Object>{
					new Map<String, Object>{
						'statusCode' => 'FIELD_CUSTOM_VALIDATION_EXCEPTION',
						'message' => message,
						'fields' => new List<String>()
					}
				}
			);
		}
		return (Database.SaveResult) JSON.deserialize(
			JSON.serialize(result),
			Database.SaveResult.class
		);
	}

	@IsTest
	static void theFailedRowsOfAPartialSaveCostOneStatement() {
		System.runAs(TestUsers.admin()) {
			Id aboutMe = UserInfo.getUserId();
			List<Database.SaveResult> results = new List<Database.SaveResult>();
			List<Id> recordIds = new List<Id>();
			for (Integer i = 0; i < 50; i++) {
				results.add(saveResult(Math.mod(i, 5) != 0, 'Row ' + i + ' was refused.'));
				recordIds.add(aboutMe);
			}

			Test.startTest();
			Integer statementsBefore = Limits.getPublishImmediateDML();
			ErrorLogger.logFailures(
				results,
				recordIds,
				'Partial save',
				ErrorLogger.SEVERITY_WARNING
			);
			ErrorLogger.logFailures(null, null, 'Partial save', ErrorLogger.SEVERITY_WARNING);
			Integer statementsAfter = Limits.getPublishImmediateDML();
			Test.stopTest();

			Assert.areEqual(1, statementsAfter - statementsBefore, 'One statement for them all.');
			Assert.areEqual(
				10,
				[
					SELECT COUNT()
					FROM Error_Log__c
					WHERE
						Context__c = 'Partial save'
						AND Record_Reference__c = :String.valueOf(aboutMe)
				],
				'Each failed row is recorded about its own record, and no row that saved is.'
			);
		}
	}

	@IsTest
	static void manyFailuresAboutTheirOwnRecordsCostOneStatement() {
		System.runAs(TestUsers.admin()) {
			Id aboutMe = UserInfo.getUserId();
			List<Exception> failures = new List<Exception>();
			for (Integer i = 0; i < 30; i++) {
				failures.add(new DmlException('Owner ' + i + ' could not be saved.'));
			}

			Test.startTest();
			Integer statementsBefore = Limits.getPublishImmediateDML();
			ErrorLogger.logEach(failures, new List<Id>{ aboutMe, null, aboutMe }, 'Each owner');
			Integer statementsAfter = Limits.getPublishImmediateDML();
			Test.stopTest();

			Assert.areEqual(1, statementsAfter - statementsBefore, 'One statement for them all.');
			List<Error_Log__c> written = [
				SELECT Occurrences__c, Record_Reference__c, Other_Record_Ids__c
				FROM Error_Log__c
				WHERE Context__c = 'Each owner'
			];
			Assert.areEqual(1, written.size(), 'One message read the same way is one entry.');
			Assert.areEqual(30, written[0].Occurrences__c, 'Every failure is counted.');
			Assert.areEqual(
				String.valueOf(aboutMe),
				written[0].Record_Reference__c,
				'It names the record; the same record is not named twice.'
			);
			Assert.isNull(written[0].Other_Record_Ids__c, 'No other record was given.');
		}
	}

	private static Error_Log_Event__e event(String message, Id recordId) {
		return new Error_Log_Event__e(
			Message__c = message,
			Context__c = 'Bulk load',
			Severity__c = 'Warning',
			Record_Reference__c = recordId == null ? null : String.valueOf(recordId)
		);
	}

	@IsTest
	static void repeatsWithinTheHourAreCountedOnOneEntryNamingTheFirstRecords() {
		System.runAs(TestUsers.admin()) {
			List<Id> userIds = new List<Id>();
			for (User someone : [SELECT Id FROM User LIMIT 15]) {
				userIds.add(someone.Id);
			}
			List<Error_Log_Event__e> events = new List<Error_Log_Event__e>();
			for (Integer i = 0; i < 2000; i++) {
				events.add(
					event('The household is missing.', userIds[Math.mod(i, userIds.size())])
				);
			}
			events.add(event('A different failure.', null));

			Test.startTest();
			ErrorLogEventHandler.handle(events);
			// A later delivery of the same failure adds to the entry already written.
			ErrorLogEventHandler.handle(
				new List<Error_Log_Event__e>{ event('The household is missing.', null) }
			);
			Test.stopTest();

			List<Error_Log__c> written = [
				SELECT Message__c, Occurrences__c, Record_Reference__c, Other_Record_Ids__c
				FROM Error_Log__c
				ORDER BY Occurrences__c
			];
			Assert.areEqual(2, written.size(), 'One entry per distinct failure.');
			Assert.areEqual('A different failure.', written[0].Message__c);
			Assert.areEqual(1, written[0].Occurrences__c, 'The different failure once.');
			Assert.areEqual('The household is missing.', written[1].Message__c);
			Assert.areEqual(2001, written[1].Occurrences__c, 'Every repeat is counted.');
			Assert.areEqual(String.valueOf(userIds[0]), written[1].Record_Reference__c);
			Integer named = Math.min(userIds.size() - 1, ErrorLogEventHandler.MORE_RECORDS);
			Assert.areEqual(
				named,
				written[1].Other_Record_Ids__c.split(',').size(),
				'The first records it happened on are named, up to the limit.'
			);
		}
	}

	@IsTest
	static void anEntryReadOrAnHourOldStartsAFreshOne() {
		System.runAs(TestUsers.admin()) {
			ErrorLogEventHandler.handle(new List<Error_Log_Event__e>{ event('Refused.', null) });
			Error_Log__c first = [SELECT Id FROM Error_Log__c LIMIT 1];
			update new Error_Log__c(Id = first.Id, Status__c = ErrorLogger.STATUS_ACKNOWLEDGED);
			ErrorLogEventHandler.handle(new List<Error_Log_Event__e>{ event('Refused.', null) });
			Error_Log__c second = [SELECT Id FROM Error_Log__c WHERE Id != :first.Id LIMIT 1];
			update new Error_Log__c(
				Id = second.Id,
				Timestamp__c = Datetime.now().addMinutes(-ErrorLogEventHandler.WINDOW_MINUTES - 1)
			);

			Test.startTest();
			ErrorLogEventHandler.handle(new List<Error_Log_Event__e>{ event('Refused.', null) });
			Test.stopTest();

			Assert.areEqual(
				3,
				[SELECT COUNT() FROM Error_Log__c WHERE Occurrences__c = 1],
				'An acknowledged entry, or one first written over an hour ago, is not added to.'
			);
		}
	}

	@IsTest
	static void withNoStatementsLeftAnEntryNeverEndsTheSaveItReports() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			// Stands for a transaction that has spent its statements: none are left to log with.
			ErrorLogWriter.reserve = Limits.getLimitDmlStatements();
			Integer publishedBefore = Limits.getPublishImmediateDML();
			Integer statementsBefore = Limits.getDmlStatements();
			ErrorLogger.logMessage('Out of room.', 'No room', ErrorLogger.SEVERITY_ERROR);
			Integer publishedAfter = Limits.getPublishImmediateDML();
			Integer statementsAfter = Limits.getDmlStatements();
			ErrorLogWriter.reserve = 2;
			Test.stopTest();

			Assert.areEqual(publishedBefore, publishedAfter, 'Nothing is published.');
			Assert.areEqual(statementsBefore, statementsAfter, 'Nothing is inserted.');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'No room'],
				'The entry goes to the debug log, and the caller keeps its statements.'
			);
		}
	}

	@IsTest
	static void loggingAlwaysLeavesTheReserveToTheCaller() {
		System.runAs(TestUsers.admin()) {
			Assert.isTrue(ErrorLogWriter.hasRoom(147, 150), 'Three left: one to log, two kept.');
			Assert.isFalse(ErrorLogWriter.hasRoom(148, 150), 'Two left: both are the caller\'s.');
			Assert.isFalse(ErrorLogWriter.hasRoom(150, 150), 'None left: nothing is spent.');
		}
	}
}
