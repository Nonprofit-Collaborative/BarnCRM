/**
 * Turns on, once, a checkbox setting that ships on but was added in an upgrade (QA-F2).
 *
 * A checkbox that ships on reaches an org that has never saved its settings through the shipped
 * defaults (`SettingsService.SHIPPED_DEFAULTS` for Core, the field's declared default for a
 * module). An org that saved its settings before the field existed has a stored record, and the
 * platform adds the new field to it as false. So the feature arrived switched off there, which is
 * how Send Weekly Admin Summary (C-54) and Ask Reminders (G-29) started off on barn-npc.
 *
 * Each package's post-install class lists the checkboxes it added this way, in
 * `SHIPPED_ON_ADDED_IN_UPGRADES`, oldest first, and only ever appends to it. Its setup steps call
 * `apply`, which sets the entries this org has not had yet, then records how many entries the
 * package has applied in the marker `Shipped_Defaults_Applied__c` on Core's settings
 * (`core:1,giving:1`). An entry is applied once: an administrator who turns the setting off
 * afterwards keeps it off, because the marker already counts it. An org that has never saved
 * the package's settings is only marked, since its shipped default already applies.
 * `scripts/ci/check-setting-defaults.py` fails the build when a new ship-on checkbox is in no
 * list.
 *
 * Runs at install and upgrade, from `scripts/org/deploy-packages.sh` and from Finish Setup,
 * because each runs the post-install class's `runSetup`. It writes through
 * `OrgSettingsSystemWriter`, as the package's own bookkeeping with no Recent Changes row, since
 * no person changed the setting. Never throws: a failure is written to the Error Log.
 */
@NamespaceAccessible
public with sharing class ShippedDefaultUpgrades {
	/** The Error Log context of a failed run. */
	@NamespaceAccessible
	public static final String CONTEXT = 'ShippedDefaultUpgrades';

	/**
	 * Sets the checkboxes in `addedInUpgrades` that this org has not had yet, then marks them as
	 * applied. Never throws.
	 *
	 * @param packageKey the package's setup key, such as `Core` or `Giving`
	 * @param settingsType the package's settings object
	 * @param addedInUpgrades the package's `SHIPPED_ON_ADDED_IN_UPGRADES`, oldest first
	 */
	@NamespaceAccessible
	public static void apply(
		String packageKey,
		Schema.SObjectType settingsType,
		List<Schema.SObjectField> addedInUpgrades
	) {
		try {
			Integer total = addedInUpgrades == null ? 0 : addedInUpgrades.size();
			Map<String, Integer> applied = appliedByPackage();
			String key = packageKey.trim().toLowerCase();
			Integer done = applied.containsKey(key) ? applied.get(key) : 0;
			if (done >= total) {
				return;
			}
			SObject stored = OrgSettingsSystemWriter.lockStored(settingsType);
			if (stored != null) {
				Map<Schema.SObjectField, Object> values = new Map<Schema.SObjectField, Object>();
				for (Integer i = done; i < total; i++) {
					values.put(addedInUpgrades[i], true);
				}
				OrgSettingsSystemWriter.saveOver(settingsType, stored, values);
			}
			applied.put(key, total);
			saveMarker(applied);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT);
		}
	}

	/** How many entries each package has applied, keyed by lower case package key. */
	@TestVisible
	private static Map<String, Integer> appliedByPackage() {
		Map<String, Integer> applied = new Map<String, Integer>();
		BarnCRM_Settings__c core = OrgSettingsSystemWriter.lockStored();
		String value = core == null ? null : core.Shipped_Defaults_Applied__c;
		for (String part : String.isBlank(value) ? new List<String>() : value.split(',')) {
			List<String> pair = part.split(':');
			if (pair.size() == 2 && pair[1].trim().isNumeric()) {
				applied.put(pair[0].trim().toLowerCase(), Integer.valueOf(pair[1].trim()));
			}
		}
		return applied;
	}

	/** Stores the counts as `core:1,giving:1`, in key order. */
	private static void saveMarker(Map<String, Integer> applied) {
		List<String> keys = new List<String>(applied.keySet());
		keys.sort();
		List<String> parts = new List<String>();
		for (String key : keys) {
			parts.add(key + ':' + applied.get(key));
		}
		OrgSettingsSystemWriter.save(
			new Map<Schema.SObjectField, Object>{
				BarnCRM_Settings__c.Shipped_Defaults_Applied__c => String.join(parts, ',')
			}
		);
	}
}
