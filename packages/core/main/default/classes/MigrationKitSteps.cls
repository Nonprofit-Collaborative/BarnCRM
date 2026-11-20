/**
 * Reads a shipped Migration Kit's steps for a module's kit test (canonical model R-MK1). The
 * Assistant that runs kits is the Migration package (ADR-0232), which no
 * module depends on, so a module's test reads its own kit row here: each step's key, kind,
 * fields, template and links, as the JSON writes them.
 */
@IsTest
@NamespaceAccessible
public class MigrationKitSteps {
	/** One step of a kit. */
	@NamespaceAccessible
	public class Step {
		@NamespaceAccessible
		public String key;
		@NamespaceAccessible
		public String kind;
		@NamespaceAccessible
		public List<String> fields = new List<String>();
		@NamespaceAccessible
		public String templateKey;
		@NamespaceAccessible
		public List<Link> links = new List<Link>();
	}

	/** A column holding a source Id an earlier step moved. */
	@NamespaceAccessible
	public class Link {
		@NamespaceAccessible
		public String column;
		@NamespaceAccessible
		public String step;
	}

	/** The named step of the shipped kit; fails the test when the kit or step is missing. */
	@NamespaceAccessible
	public static Step step(String kitKey, String stepKey) {
		List<Migration_Kit__mdt> kits = [
			SELECT Steps_JSON__c
			FROM Migration_Kit__mdt
			WHERE DeveloperName = :kitKey
			WITH SYSTEM_MODE
		];
		Assert.areEqual(1, kits.size(), 'the kit ships: ' + kitKey);
		for (Object read : (List<Object>) JSON.deserializeUntyped(kits[0].Steps_JSON__c)) {
			Map<String, Object> written = (Map<String, Object>) read;
			if (written.get('key') == stepKey) {
				Step step = (Step) JSON.deserialize(JSON.serialize(written), Step.class);
				step.fields = step.fields == null ? new List<String>() : step.fields;
				step.links = step.links == null ? new List<Link>() : step.links;
				return step;
			}
		}
		Assert.fail('the kit ' + kitKey + ' has the step ' + stepKey);
		return null;
	}
}
