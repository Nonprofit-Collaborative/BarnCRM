/**
 * Who owns a record moving into a territory (R-TM2): kept, the territory's owner, members in
 * turn skipping anyone full, or the member with the most room.
 */
@IsTest(testFor='ApexClass:TerritoryRouting')
private class TerritoryRoutingTest {
	// runs-as: deploying user (pure routing logic: no DML or SOQL)

	private static final Id ANA = '005000000000001';
	private static final Id BEN = '005000000000002';
	private static final Id CHO = '005000000000003';

	private static TerritoryRouting.Pool pool(String routing, List<Integer> capacities) {
		TerritoryRouting.Pool made = new TerritoryRouting.Pool();
		made.routing = routing;
		made.territoryOwner = CHO;
		made.users = new List<Id>{ ANA, BEN };
		made.capacities = capacities;
		return made;
	}

	@IsTest
	static void keepOwnerAndTerritoryOwner() {
		Assert.isNull(
			TerritoryRouting.ownerFor(pool(TerritoryRouting.KEEP_OWNER, new List<Integer>{ 1, 1 })),
			'Keep Owner changes nothing'
		);
		Assert.areEqual(
			CHO,
			TerritoryRouting.ownerFor(
				pool(TerritoryRouting.TERRITORY_OWNER, new List<Integer>{ null, null })
			),
			'The territory owner'
		);
		TerritoryRouting.Pool empty = pool(TerritoryRouting.ROUND_ROBIN, new List<Integer>());
		empty.users.clear();
		Assert.isNull(TerritoryRouting.ownerFor(empty), 'No members, owner kept');
	}

	@IsTest
	static void roundRobinTakesTurnsAndSkipsAFullMember() {
		TerritoryRouting.Pool turns = pool(
			TerritoryRouting.ROUND_ROBIN,
			new List<Integer>{ 1, null }
		);
		turns.next = 0;
		Assert.areEqual(ANA, TerritoryRouting.ownerFor(turns), 'Ana first');
		Assert.areEqual(BEN, TerritoryRouting.ownerFor(turns), 'Then Ben');
		Assert.areEqual(BEN, TerritoryRouting.ownerFor(turns), 'Ana is full, so Ben again');
		Assert.areEqual(0, turns.next, 'The turn comes back round');
	}

	@IsTest
	static void capacityGoesToTheMostRoomAndCountsWhenEveryoneIsFull() {
		TerritoryRouting.Pool room = pool(TerritoryRouting.CAPACITY, new List<Integer>{ 3, 2 });
		room.owned.put(ANA, 1);
		Assert.areEqual(ANA, TerritoryRouting.ownerFor(room), 'A tie goes to the first in turn');
		Assert.areEqual(BEN, TerritoryRouting.ownerFor(room), 'Ben has more room now');
		Assert.areEqual(ANA, TerritoryRouting.ownerFor(room), 'A tie again: Ana fills');
		Assert.areEqual(BEN, TerritoryRouting.ownerFor(room), 'Ben fills');
		Assert.isNull(TerritoryRouting.ownerFor(room), 'Nobody has room');
		Assert.areEqual(1, room.noRoom, 'Counted');
		TerritoryRouting.Pool open = pool(TerritoryRouting.CAPACITY, new List<Integer>{ 5, null });
		Assert.areEqual(BEN, TerritoryRouting.ownerFor(open), 'No limit has the most room');
	}
}
