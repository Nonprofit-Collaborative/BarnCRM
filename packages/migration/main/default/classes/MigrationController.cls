/**
 * The Apex surface of the Migration Assistant tab (MIG-01): what the tab offers, a kit's view
 * and the three actions that move its run on. Loading, results and undo of an import step are
 * the Super Importer's own (`ImportController`), called by the page with the step's batch. Every
 * method needs Manage BarnCRM Settings, checked in `MigrationKitService` and
 * `NpspHouseholdAdoptionService`.
 */
public with sharing class MigrationController {
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
		'MigrationController',
		null,
		Label.Core_UnexpectedError
	);

	/** What the tab offers here: the kits and the two household tools. */
	public class Home {
		@AuraEnabled
		public List<MigrationKitService.KitRef> kits;
		/** Adopt NPSP Households applies here (NPSP detected, or a run to undo). */
		@AuraEnabled
		public Boolean npspHouseholds;
		/** Convert Nonprofit Cloud Households applies here (Mirror finds them, or a run to undo). */
		@AuraEnabled
		public Boolean npcHouseholds;
	}

	@AuraEnabled
	public static Home getHome() {
		try {
			Home home = new Home();
			home.kits = MigrationKitService.offeredKits();
			home.npspHouseholds = NpspHouseholdAdoptionService.isOffered();
			home.npcHouseholds = NpspHouseholdAdoptionService.isNpcOffered();
			return home;
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Not cacheable, so Refresh reads the run and the source again. */
	@AuraEnabled
	public static MigrationKitService.KitView getKit(String kitKey) {
		try {
			return MigrationKitService.view(kitKey);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Starts an import step: reads the source into a preview. */
	@AuraEnabled
	public static MigrationKitService.KitView startStep(String kitKey, String stepKey) {
		try {
			MigrationKitService.startStep(kitKey, stepKey);
			return MigrationKitService.view(kitKey);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Marks a tool step done, or not done. */
	@AuraEnabled
	public static MigrationKitService.KitView setToolStep(String kitKey, String stepKey, Boolean done) {
		try {
			MigrationKitService.markToolStep(kitKey, stepKey, done);
			return MigrationKitService.view(kitKey);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}

	/** Ticks or unticks a retire checklist item. */
	@AuraEnabled
	public static MigrationKitService.KitView setChecklistItem(String kitKey, String itemKey, Boolean ticked) {
		try {
			MigrationKitService.tick(kitKey, itemKey, ticked);
			return MigrationKitService.view(kitKey);
		} catch (Exception e) {
			throw ERRORS.wrap(e);
		}
	}
}
