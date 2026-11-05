/**
 * A Contact handler that fails for some records, used only by the dispatcher's partial save
 * tests (ADR-0165 dispatcher error contract).
 *
 * It is a top-level public class with a no-argument constructor because the registry builds it by
 * name (ADR-0017). It fails whenever a record in front of it has a last name starting with
 * `Refuse`, after doing its work for every record in front of it: in a before context it fills the
 * description, in an after context it saves one Saved Query per person. So a test can tell the
 * work of a failed attempt, which the dispatcher must undo, from the work that stays.
 */
@IsTest
public class TestFailingHandler extends TriggerHandler {
	public static final String REFUSED_PREFIX = 'Refuse';
	public static final String SEEN = 'Seen by the test handler';

	/** Which phase fails: 'before' or 'after'. */
	public static String failIn = 'before';
	/** How many times a context method ran, every attempt counted. */
	public static Integer attempts = 0;

	public override void beforeInsert() {
		attempts++;
		for (Contact person : (List<Contact>) newRecords()) {
			person.Description = SEEN;
		}
		if (failIn == 'before') {
			failForRefusedNames();
		}
	}

	public override void afterInsert() {
		attempts++;
		List<Saved_Query__c> notes = new List<Saved_Query__c>();
		for (Contact person : (List<Contact>) newRecords()) {
			notes.add(new Saved_Query__c(Name = person.LastName, Object_Name__c = 'Contact'));
		}
		Database.insert(notes, AccessLevel.SYSTEM_MODE);
		if (failIn == 'after') {
			failForRefusedNames();
		}
	}

	private void failForRefusedNames() {
		for (Contact person : (List<Contact>) newRecords()) {
			if (person.LastName != null && person.LastName.startsWith(REFUSED_PREFIX)) {
				throw new IllegalArgumentException('A value this handler cannot use.');
			}
		}
	}
}
