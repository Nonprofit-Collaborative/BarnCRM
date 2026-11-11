/**
 * The first-fit rule both waitlists share (ADR-NEXT volunteer self-service and waitlists,
 * decision 5), on records held in memory: Core has no module object, so accounts stand in, the
 * parent account as the shift or program and Number of Employees as a group's size.
 */
// runs-as: deploying user (pure logic: records held in memory, no DML or SOQL)
@IsTest(testFor='ApexClass:WaitlistQueue')
private class WaitlistQueueTest {
	private static final Id FULL_PARENT = Id.valueOf('001000000000001');
	private static final Id OPEN_PARENT = Id.valueOf('001000000000002');

	private static Account candidate(Id parentId, Integer size) {
		return new Account(ParentId = parentId, NumberOfEmployees = size);
	}

	@IsTest
	static void fitsInOrderAndPassesOverWhatDoesNotFit() {
		Map<Id, Decimal> free = new Map<Id, Decimal>{ FULL_PARENT => 3 };
		Account big = candidate(FULL_PARENT, 2);
		Account tooBig = candidate(FULL_PARENT, 4);
		Account single = candidate(FULL_PARENT, 1);
		Account oneMore = candidate(FULL_PARENT, 1);

		List<SObject> fits = WaitlistQueue.fitting(
			free,
			new List<SObject>{ big, tooBig, single, oneMore },
			'ParentId',
			'NumberOfEmployees'
		);

		Assert.areEqual(2, fits.size(), 'Two fit in three places');
		Assert.isTrue(fits[0] === big, 'The oldest goes first');
		Assert.isTrue(fits[1] === single, 'A group too big is passed over for a smaller one');
		Assert.areEqual(0, free.get(FULL_PARENT), 'Every place is taken');
	}

	@IsTest
	static void aParentWithNoLimitTakesEveryone() {
		Map<Id, Decimal> free = new Map<Id, Decimal>{ FULL_PARENT => 0 };
		List<SObject> fits = WaitlistQueue.fitting(
			free,
			new List<SObject>{
				candidate(OPEN_PARENT, 9),
				candidate(null, 1),
				candidate(FULL_PARENT, 1)
			},
			'ParentId',
			null
		);
		Assert.areEqual(
			2,
			fits.size(),
			'No limit and no parent always fit; a full parent takes nobody'
		);
	}

	@IsTest
	static void blankOrBelowOneTakesOnePlace() {
		Assert.areEqual(
			1,
			WaitlistQueue.placesOf(candidate(null, null), 'NumberOfEmployees'),
			'Blank'
		);
		Assert.areEqual(1, WaitlistQueue.placesOf(candidate(null, 0), 'NumberOfEmployees'), 'Zero');
		Assert.areEqual(5, WaitlistQueue.placesOf(candidate(null, 5), 'NumberOfEmployees'), 'Five');
		Assert.areEqual(1, WaitlistQueue.placesOf(candidate(null, 5), null), 'No places field');
	}
}
