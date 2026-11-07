/**
 * The relationship card's one server call. The card reads relationships through GraphQL and
 * saves through Lightning Data Service; only which types it may offer for a new relationship
 * needs the server, because an administrator can turn a shipped type off
 * (ADR-0170).
 */
public with sharing class RelationshipController {
	/** The Type values not offered for a new relationship, lower case. */
	@AuraEnabled(cacheable=true)
	public static List<String> getTurnedOffTypes() {
		List<String> types = new List<String>(RelationshipService.turnedOffTypes());
		types.sort();
		return types;
	}

	/** Whether the Relationships feature is on: the card shows nothing while it is off. */
	@AuraEnabled(cacheable=true)
	public static Boolean isFeatureOn() {
		return FeatureSwitchService.isOn(FeatureSwitchService.RELATIONSHIPS);
	}
}
