/**
 * Who owns a record that moves into a territory (canonical model R-TM2, C-40b). A pool holds one
 * territory's routing, members and counts for one run; `ownerFor` picks the owner and counts it.
 * Pure logic with no query or save, so the rules are tested on their own (plan 9.9).
 */
public with sharing class TerritoryRouting {
	public static final String KEEP_OWNER = 'Keep Owner';
	public static final String TERRITORY_OWNER = 'Territory Owner';
	public static final String ROUND_ROBIN = 'Round Robin';
	public static final String CAPACITY = 'Capacity';
	/** The room of a member with no capacity: never full, and always more than a capped one. */
	private static final Long UNLIMITED = 1000000000L;

	/** One territory's routing for a run. */
	public class Pool {
		public String routing = KEEP_OWNER;
		public Id territoryOwner;
		/** Active members in turn order, and each one's capacity (null: no limit). */
		public List<Id> users = new List<Id>();
		public List<Integer> capacities = new List<Integer>();
		/** Records of the territory each member owns: counted once, then what the run gives. */
		public Map<Id, Integer> owned = new Map<Id, Integer>();
		/** Where round robin goes next. */
		public Integer next = 0;
		/** Records that moved in with no member left with room. */
		public Integer noRoom = 0;

		/** True when the routing reads the members' counts. */
		public Boolean needsCounts() {
			return (routing == ROUND_ROBIN || routing == CAPACITY) && !users.isEmpty();
		}
	}

	/** The owner a record moving into the pool's territory gets, or null to keep its owner. */
	public static Id ownerFor(Pool pool) {
		if (pool.routing == TERRITORY_OWNER) {
			return pool.territoryOwner;
		}
		if (!pool.needsCounts()) {
			return null;
		}
		Integer chosen = pool.routing == ROUND_ROBIN ? nextInTurn(pool) : mostRoom(pool);
		if (chosen == null) {
			pool.noRoom++;
			return null;
		}
		Id user = pool.users[chosen];
		pool.owned.put(user, owned(pool, user) + 1);
		return user;
	}

	/** The next member in turn with room, from where the last one stopped. */
	private static Integer nextInTurn(Pool pool) {
		Integer size = pool.users.size();
		Integer start = pool.next == null ? 0 : Math.mod(Math.abs(pool.next), size);
		for (Integer step = 0; step < size; step++) {
			Integer index = Math.mod(start + step, size);
			if (room(pool, index) > 0) {
				pool.next = Math.mod(index + 1, size);
				return index;
			}
		}
		return null;
	}

	/** The member with the most room; the first in turn order wins a tie. */
	private static Integer mostRoom(Pool pool) {
		Integer best;
		Long bestRoom = 0;
		for (Integer index = 0; index < pool.users.size(); index++) {
			Long space = room(pool, index);
			if (space > bestRoom) {
				best = index;
				bestRoom = space;
			}
		}
		return best;
	}

	private static Long room(Pool pool, Integer index) {
		Integer capacity = pool.capacities[index];
		Integer held = owned(pool, pool.users[index]);
		return capacity == null ? UNLIMITED - held : (Long) (capacity - held);
	}

	private static Integer owned(Pool pool, Id user) {
		Integer held = pool.owned.get(user);
		return held == null ? 0 : held;
	}
}
