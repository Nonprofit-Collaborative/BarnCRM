/**
 * The certification panel's controller (`certificationActions`, G-22e): what a member
 * certification can do now, and Grant, Renew and Revoke. Thin: plain shapes, user mode, the
 * rules in `CertificationService`.
 */
public with sharing class CertificationController {
	/** The panel's state for one member certification. */
	public class Panel {
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Date expiresOn;
		@AuraEnabled
		public Decimal openCredits;
		@AuraEnabled
		public Decimal creditsRequired;
		@AuraEnabled
		public Boolean canEdit = false;
		@AuraEnabled
		public Boolean canGrant = false;
		@AuraEnabled
		public Boolean canRevoke = false;
		/** Why Renew is not offered now, or null when it is. */
		@AuraEnabled
		public String renewRefusal;
	}

	@AuraEnabled
	public static Panel panel(Id holdingId) {
		try {
			Member_Certification__c holding = CertificationService.read(holdingId);
			Panel result = new Panel();
			result.status = holding.Status__c;
			result.expiresOn = holding.Expires_On__c;
			result.openCredits = holding.Open_Credits__c == null ? 0 : holding.Open_Credits__c;
			result.creditsRequired = holding.Certification__r.Credits_Required__c;
			result.canEdit = Schema.SObjectType.Member_Certification__c.isUpdateable();
			result.canGrant = result.canEdit && holding.Status__c != CertificationService.ACTIVE;
			result.canRevoke = result.canEdit && holding.Status__c != CertificationService.REVOKED;
			result.renewRefusal = CertificationService.renewRefusal(holding);
			return result;
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'CertificationController.panel', true);
		}
	}

	@AuraEnabled
	public static Panel grant(Id holdingId) {
		try {
			CertificationService.grant(holdingId);
			return panel(holdingId);
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'CertificationController.grant', true);
		}
	}

	@AuraEnabled
	public static Panel renew(Id holdingId) {
		try {
			CertificationService.renew(holdingId);
			return panel(holdingId);
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'CertificationController.renew', true);
		}
	}

	@AuraEnabled
	public static Panel revoke(Id holdingId) {
		try {
			CertificationService.revoke(holdingId);
			return panel(holdingId);
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'CertificationController.revoke', true);
		}
	}
}
