/**
 * Contact Point Sync on `Household_Member__c` (registry row `Contact_Point_Sync_Membership`;
 * ADR-0176 contact point sync module, decisions 4, 7 and 15). A switch on the Automation page
 * that Pause All covers.
 *
 * Where households are kept as membership rows (junction mode), a person who joins, leaves or
 * moves household takes the household's addresses with them. After the save, this syncs the
 * address copies of every person whose membership was added, changed, ended, removed or
 * restored, in the same transaction (or an immediately queued job when the transaction has no
 * room), not at the person's next save. In contact mode the membership is the person's account,
 * which the Contact handler already follows. Never fails a save.
 */
@NamespaceAccessible
public with sharing class ContactPointMembershipHandler extends TriggerHandler {
	private static final Set<String> ADDRESS_ONLY = new Set<String>{ ContactPointPlan.ADDRESS };

	/** Built by name from Core's dispatcher, so it needs a public constructor. */
	@NamespaceAccessible
	public ContactPointMembershipHandler() {
		return;
	}

	public override void afterInsert() {
		sync(newRecords(), null);
	}

	public override void afterUpdate() {
		sync(newRecords(), oldRecordsById());
	}

	public override void afterDelete() {
		sync(oldRecords(), null);
	}

	public override void afterUndelete() {
		sync(newRecords(), null);
	}

	private static void sync(List<SObject> rows, Map<Id, SObject> before) {
		if (
			rows == null ||
			rows.isEmpty() ||
			!ContactPointSyncService.activeKinds().contains(ContactPointPlan.ADDRESS)
		) {
			return;
		}
		// Also forgets any household answer given earlier in this transaction.
		HouseholdService.MembershipChange change = HouseholdService.membershipChangeOf(
			rows,
			before
		);
		// A person being erased is synced once when the erasure ends (ADR-0193 erasure start seam).
		ContactPointSyncService.syncOrQueue(
			ContactPointSyncService.withoutHeld(change.personIds),
			ADDRESS_ONLY
		);
	}
}
