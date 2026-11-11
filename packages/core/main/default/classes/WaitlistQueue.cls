/**
 * The one first-fit rule both waitlists use (ADR-NEXT volunteer self-service and waitlists,
 * decision 5): a full shift in Volunteers (V-14) and a full program in Programs (P-09). Plain
 * Apex with no query or save, so each module counts its own places and saves its own records,
 * and Core names no module object. The same rule decides who is waitlisted on save and who is
 * promoted when places free up.
 */
@NamespaceAccessible
public with sharing class WaitlistQueue {
	/**
	 * The candidates that fit, in the order given, each taking its places from its parent's free
	 * places. A candidate whose parent has no entry in `free` has no limit and always fits. One
	 * that does not fit is passed over, so a smaller one behind it can still go.
	 *
	 * @param free places free per parent, reduced in place by each candidate that fits
	 * @param candidates the records to place, oldest first
	 * @param parentField the field naming the parent, such as a shift or a program
	 * @param placesField the field holding how many places one takes, or null for one each; a
	 *   blank value or one below 1 takes one place
	 */
	@NamespaceAccessible
	public static List<SObject> fitting(
		Map<Id, Decimal> free,
		List<SObject> candidates,
		String parentField,
		String placesField
	) {
		List<SObject> fits = new List<SObject>();
		for (SObject candidate : candidates) {
			Id parentId = (Id) candidate.get(parentField);
			if (parentId == null || !free.containsKey(parentId)) {
				fits.add(candidate);
				continue;
			}
			Decimal places = placesOf(candidate, placesField);
			Decimal left = free.get(parentId);
			if (places <= left) {
				fits.add(candidate);
				free.put(parentId, left - places);
			}
		}
		return fits;
	}

	/** How many places a record takes: its places field, or 1 when blank or below 1. */
	@NamespaceAccessible
	public static Decimal placesOf(SObject record, String placesField) {
		Object value = placesField == null ? null : record.get(placesField);
		Decimal places = value == null ? 1 : Decimal.valueOf(String.valueOf(value));
		return places < 1 ? 1 : places;
	}
}
