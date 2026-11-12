/**
 * Whether the person page's engagement meter shows (C-64, canonical model R-ES1). The meter
 * reads the score itself through Lightning Data Service.
 */
public with sharing class EngagementScoreController {
	/** True while the organization has scoring on. */
	@AuraEnabled(cacheable=true)
	public static Boolean isFeatureOn() {
		return EngagementScore.isOn();
	}
}
