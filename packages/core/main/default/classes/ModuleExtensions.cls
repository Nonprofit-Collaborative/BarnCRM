/**
 * Every module's wiring into Core, read from the module catalog (`BarnCRM_Module__mdt`) as
 * data (ADR-0017 decision 3 as extended by D-200 S1): the classes each module registers for
 * Core's extension seams (`Extensions__c`) and the permission sets Core's access sync gives
 * (`Access_By_Permission_Set__c`, `Access_By_Role__c`). Core names no module class in code.
 *
 * A seam is the name of the Core interface the classes implement, for example
 * `NightlyStepProvider`. Modules are asked in catalog order (Sort Order, then name). A class is
 * found by namespace and name (`NamespaceUtil.build`) once per transaction; one that is not
 * installed is skipped, and one that cannot be built or does not implement the seam is logged
 * and skipped, since no page or job may fail over a module it can do without.
 *
 * The catalog is read with SOQL, not `getAll`, because `Extensions__c` is a long text field.
 */
@NamespaceAccessible
public with sharing class ModuleExtensions {
	private static final String CONTEXT = 'ModuleExtensions';

	/** Stands in for the shipped catalog in Core's tests, where no module is installed. */
	@TestVisible
	private static List<BarnCRM_Module__mdt> catalogOverride;

	/** Stand-ins by seam, then module key, injected by tests; a null stands for not installed. */
	@TestVisible
	private static Map<String, Map<String, Object>> stubs = new Map<String, Map<String, Object>>();

	/** Seams a test sees only its stand-ins for, as if no module were installed. */
	@TestVisible
	private static Set<String> stubsOnly = new Set<String>();

	private static List<BarnCRM_Module__mdt> rows;
	private static Map<String, Object> built = new Map<String, Object>();

	/**
	 * Every installed module's class for this seam, in catalog order, each built once per
	 * transaction. Never null.
	 *
	 * @param seam the Core interface the classes implement, for example `HealthCheckExtension`
	 */
	@NamespaceAccessible
	public static List<Object> all(Type seam) {
		return byModule(seam).values();
	}

	/** The same, keyed by module (the catalog DeveloperName), in catalog order. */
	@NamespaceAccessible
	public static Map<String, Object> byModule(Type seam) {
		String name = seamName(seam);
		Map<String, Object> stubbed = stubs.containsKey(name)
			? stubs.get(name)
			: new Map<String, Object>();
		Map<String, Object> found = new Map<String, Object>();
		if (!stubsOnly.contains(name)) {
			for (BarnCRM_Module__mdt row : catalog()) {
				if (stubbed.containsKey(row.DeveloperName)) {
					continue;
				}
				for (String className : classesFor(row, name)) {
					Object instance = build(className, seam);
					if (instance != null) {
						found.put(row.DeveloperName, instance);
						break;
					}
				}
			}
		}
		for (String moduleKey : stubbed.keySet()) {
			if (stubbed.get(moduleKey) != null) {
				found.put(moduleKey, stubbed.get(moduleKey));
			}
		}
		return found;
	}

	/** The first installed module's class for this seam, or null when none is installed. */
	@NamespaceAccessible
	public static Object first(Type seam) {
		List<Object> found = all(seam);
		return found.isEmpty() ? null : found[0];
	}

	/** One module's class for this seam, or null when the module has none installed. */
	@NamespaceAccessible
	public static Object forModule(Type seam, String moduleKey) {
		Map<String, Object> found = byModule(seam);
		for (String key : found.keySet()) {
			if (key.equalsIgnoreCase(moduleKey)) {
				return found.get(key);
			}
		}
		return null;
	}

	/**
	 * Has a module's test stand `instance` in for that module's class for the seam, where
	 * `@TestVisible` does not reach once the packages are separate. Does nothing outside a test.
	 *
	 * @param only true to see no other module's class for the seam
	 */
	@NamespaceAccessible
	public static void stubForTest(Type seam, String moduleKey, Object instance, Boolean only) {
		if (!Test.isRunningTest()) {
			return;
		}
		String name = seamName(seam);
		if (!stubs.containsKey(name)) {
			stubs.put(name, new Map<String, Object>());
		}
		stubs.get(name).put(moduleKey, instance);
		if (only == true) {
			stubsOnly.add(name);
		}
	}

	// -------------------------------------------------------------------------------------
	// Access maps
	// -------------------------------------------------------------------------------------

	/** The catalog keys of every module that names permission sets for the access sync. */
	@NamespaceAccessible
	public static List<String> modulesWithAccess() {
		List<String> keys = new List<String>();
		for (BarnCRM_Module__mdt row : catalog()) {
			if (
				String.isNotBlank(row.Access_By_Permission_Set__c) ||
				String.isNotBlank(row.Access_By_Role__c)
			) {
				keys.add(row.DeveloperName);
			}
		}
		return keys;
	}

	/** Each of the module's sets and the Core permission sets whose holders get it. */
	@NamespaceAccessible
	public static Map<String, List<String>> setsByPermissionSet(String moduleKey) {
		BarnCRM_Module__mdt row = row(moduleKey);
		return parseMap(row == null ? null : row.Access_By_Permission_Set__c);
	}

	/** Each of the module's sets and the BarnCRM roles (permission set groups) that get it. */
	@NamespaceAccessible
	public static Map<String, List<String>> setsByRole(String moduleKey) {
		BarnCRM_Module__mdt row = row(moduleKey);
		return parseMap(row == null ? null : row.Access_By_Role__c);
	}

	/** `Set=A,B;Other=C` read as a map of set to list, in written order. */
	@TestVisible
	private static Map<String, List<String>> parseMap(String written) {
		Map<String, List<String>> bySet = new Map<String, List<String>>();
		for (String entry : String.isBlank(written) ? new List<String>() : written.split(';')) {
			String setName = entry.substringBefore('=').trim();
			if (String.isBlank(setName)) {
				continue;
			}
			List<String> holders = new List<String>();
			for (String holder : entry.substringAfter('=').split(',')) {
				if (String.isNotBlank(holder)) {
					holders.add(holder.trim());
				}
			}
			bySet.put(setName, holders);
		}
		return bySet;
	}

	// -------------------------------------------------------------------------------------
	// Catalog
	// -------------------------------------------------------------------------------------

	private static BarnCRM_Module__mdt row(String moduleKey) {
		for (BarnCRM_Module__mdt candidate : catalog()) {
			if (candidate.DeveloperName.equalsIgnoreCase(moduleKey)) {
				return candidate;
			}
		}
		return null;
	}

	private static List<BarnCRM_Module__mdt> catalog() {
		if (catalogOverride != null) {
			return catalogOverride;
		}
		if (rows == null) {
			rows = new List<BarnCRM_Module__mdt>();
			try {
				rows = [
					SELECT
						DeveloperName,
						Sort_Order__c,
						Extensions__c,
						Access_By_Permission_Set__c,
						Access_By_Role__c
					FROM BarnCRM_Module__mdt
					ORDER BY Sort_Order__c ASC NULLS LAST, DeveloperName ASC
					LIMIT 200
				];
			} catch (Exception failed) {
				ErrorLogger.log(failed, CONTEXT);
			}
		}
		return rows;
	}

	/** The classes a row registers for the seam, from lines written `Seam: Class, Class`. */
	private static List<String> classesFor(BarnCRM_Module__mdt row, String seamName) {
		List<String> classNames = new List<String>();
		if (String.isBlank(row.Extensions__c)) {
			return classNames;
		}
		for (String line : row.Extensions__c.split('[\\n;]')) {
			if (!line.substringBefore(':').trim().equalsIgnoreCase(seamName)) {
				continue;
			}
			for (String className : line.substringAfter(':').split(',')) {
				if (String.isNotBlank(className)) {
					classNames.add(className.trim());
				}
			}
		}
		return classNames;
	}

	private static Object build(String className, Type seam) {
		String key = seamName(seam) + ':' + className;
		if (!built.containsKey(key)) {
			built.put(key, NamespaceUtil.build(className, seam, CONTEXT));
		}
		return built.get(key);
	}

	/** The interface's name without a namespace: `barn.HealthCheckExtension` is the seam `HealthCheckExtension`. */
	private static String seamName(Type seam) {
		String name = seam.getName();
		return name.contains('.') ? name.substringAfterLast('.') : name;
	}
}
