/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add the nightly address
 * check to the one nightly run (ADR-0166; ADR-0209 `0209-address-verification-module.md`,
 * decision 5). Its switch ships on; it runs only while the module is on, the chosen provider's
 * keys are entered and the Nightly Limit is above 0, so a fresh install looks nothing up.
 */
@NamespaceAccessible
public with sharing class AddressVerificationNightlyJobProvider implements NightlyStepProvider {
	public static final String STEP_KEY = 'AddressVerification';

	@NamespaceAccessible
	public AddressVerificationNightlyJobProvider() {
		return;
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{
			new NightlyStep(
					STEP_KEY,
					BarnHelp.text('AddressVerification', 'AddressVerification_NightlyStep'),
					3,
					30,
					new AddressVerificationJob()
				)
				.withSwitch(true)
				.activeWhen(
					AddressVerifier.isOn() &&
						AddressVerifier.isReady() &&
						AddressVerifier.settings().Nightly_Limit__c > 0
				)
		};
	}
}
