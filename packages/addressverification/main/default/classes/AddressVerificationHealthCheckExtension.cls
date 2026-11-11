/**
 * Address Verification's checks in Health Check (ADR-NEXT `NEXT-address-verification-module.md`,
 * decision 7; ADR-0057's extension seam). Core finds this class by name
 * (`HealthCheckExtensions.EXTENSION_CLASSES`). Asked only while the module is on, of a viewer
 * who may manage settings:
 * - the chosen provider's keys not entered (warning);
 * - Current addresses still Unverified 30 days after they were last changed (info, the count).
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class AddressVerificationHealthCheckExtension implements HealthCheckExtension {
	private static final Integer WAIT_DAYS = 30;

	@NamespaceAccessible
	public AddressVerificationHealthCheckExtension() {
		// Built by name from Core (HealthCheckExtensions), so it needs a public constructor.
	}

	public List<HealthCheckService.Finding> findings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		if (!HealthCheckService.canManageSettings() || !AddressVerifier.isOn()) {
			return found;
		}
		try {
			if (!AddressVerifier.isReady()) {
				found.add(
					new HealthCheckService.Finding(
						'address_verification_keys_missing',
						BarnHelp.text(
							'AddressVerification',
							'AddressVerification_Health_KeysMissingTitle'
						),
						BarnHelp.text(
							'AddressVerification',
							'AddressVerification_Health_KeysMissingDetail',
							new List<Object>{ AddressVerifier.provider() }
						),
						HealthCheckService.SEVERITY_WARNING,
						HealthCheckService.CATEGORY_SETTINGS
					)
				);
				return found;
			}
			Integer waiting = waitingCount();
			if (waiting > 0) {
				found.add(
					new HealthCheckService.Finding(
						'address_verification_waiting',
						BarnHelp.text(
							'AddressVerification',
							'AddressVerification_Health_WaitingTitle'
						),
						BarnHelp.text(
							'AddressVerification',
							'AddressVerification_Health_WaitingDetail',
							new List<Object>{ waiting }
						),
						HealthCheckService.SEVERITY_INFO,
						HealthCheckService.CATEGORY_SETTINGS
					)
				);
			}
		} catch (Exception e) {
			found.add(HealthCheckService.checkFailed('address_verification', e));
		}
		return found;
	}

	@TestVisible
	private static Integer waitingCount() {
		DateTime before = DateTime.now().addDays(-WAIT_DAYS);
		return [
			SELECT COUNT()
			FROM Address__c
			WHERE
				(Status__c = 'Current'
				OR Status__c = NULL)
				AND Verification_Status__c = :AddressVerifier.UNVERIFIED
				AND LastModifiedDate < :before
			WITH USER_MODE
			LIMIT 10000
		];
	}
}
