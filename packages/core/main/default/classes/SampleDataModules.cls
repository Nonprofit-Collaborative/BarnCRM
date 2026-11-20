/**
 * The module sample data sets installed in this org, in load order (C-10).
 *
 * Core names each module's implementation as a string and resolves it with `Type.forName`,
 * which is the mechanism ADR-0017 settled for calling into a package Core cannot compile
 * against. A module that is not installed simply does not resolve, and every caller here
 * copes with the empty list.
 *
 * Loading is one module at a time on purpose. Core's stage batch finishes by starting the
 * first module, and each module's own load finishes by calling `startAfter` with its name,
 * which starts the module after it (the order of MODULE_CLASS_NAMES below; Logic Models
 * follows Programs because its models name the Programs sample programs), so a module never
 * needs to know which modules come after it. A module runs its stages through
 * SampleDataStageBatch (see SampleDataStages), because a queueable chain stops after five
 * jobs in Developer Edition, trial and scratch orgs.
 */
@NamespaceAccessible
public with sharing class SampleDataModules {
	/**
	 * Module sample data sets in load order: a JSON static resource of this name that Core
	 * loads (SampleDataFile), or a class of this name that is public, `@NamespaceAccessible`,
	 * has a no-argument constructor, and implements SampleDataModule.
	 */
	private static final List<String> MODULE_CLASS_NAMES = new List<String>{
		'CoreSampleData',
		'GivingSampleData',
		'VolunteersSampleData',
		'ProgramsSampleData',
		'LogicModelsSampleData',
		'FundersSampleData',
		'EventsSampleData',
		'MembershipsSampleData',
		'ScholarshipsSampleData',
		'ProjectsSampleData',
		'CorporateHubSampleData',
		'FormsSampleData',
		'PortalSampleData',
		'TerritorySampleData'
	};

	/** Injected by the tests, which have no other package to resolve a real module from. */
	@NamespaceAccessible
	@TestVisible
	public static List<SampleDataModule> moduleOverride;

	/** Injected by the tests in place of the Sample Data package's host. */
	@TestVisible
	private static SampleDataHost hostOverride;

	/** One module sample set's own number, as the status card shows it. */
	@NamespaceAccessible
	public class ModuleCount {
		/** The module's stable name, for example 'Giving'. */
		@AuraEnabled
		public String name;
		/** The module's own wording for what the number counts, for example 'Gifts'. */
		@AuraEnabled
		public String label;
		@AuraEnabled
		public Integer recordCount;
	}

	/**
	 * The BarnCRM Sample Data package's host, found by the class name its catalog row gives
	 * (ADR-0057), or null when the package is not installed.
	 */
	@NamespaceAccessible
	public static SampleDataHost host() {
		if (hostOverride != null) {
			return hostOverride;
		}
		return (SampleDataHost) ModuleExtensions.first(SampleDataHost.class);
	}

	/** The host, or a SampleDataException that says to install the Sample Data package. */
	public static SampleDataHost requireHost() {
		SampleDataHost sampleHost = host();
		if (sampleHost == null) {
			throw new SampleDataException(BarnHelp.text('Core', 'Core_SampleData_PackageMissing'));
		}
		return sampleHost;
	}

	/** Each class looked up so far this transaction, null when it is not installed. */
	private static Map<String, SampleDataModule> found = new Map<String, SampleDataModule>();

	/** Every module sample data set this org actually has, in load order. */
	public static List<SampleDataModule> installed() {
		if (moduleOverride != null) {
			return moduleOverride;
		}
		List<SampleDataModule> modules = new List<SampleDataModule>();
		if (!found.keySet().containsAll(MODULE_CLASS_NAMES)) {
			// One query for every module's file, not one per module.
			SampleDataFile.preload(MODULE_CLASS_NAMES);
		}
		for (String className : MODULE_CLASS_NAMES) {
			if (!found.containsKey(className)) {
				found.put(className, resolve(className));
			}
			SampleDataModule module = found.get(className);
			if (module != null) {
				modules.add(module);
			}
		}
		return modules;
	}

	/** Starts the first installed module's load, if there is one. */
	@NamespaceAccessible
	public static void startFirst() {
		start(0);
	}

	/**
	 * Starts the module that loads after the named one. Called by a module's own last job,
	 * so the chain carries on without Core knowing which modules exist.
	 */
	@NamespaceAccessible
	public static void startAfter(String moduleName) {
		List<SampleDataModule> modules = installed();
		for (Integer index = 0; index < modules.size(); index++) {
			if (modules[index].moduleName() == moduleName) {
				start(index + 1);
				return;
			}
		}
	}

	/**
	 * Starts the removal with the last installed module, or with Core's own when there is none.
	 * Modules go in the reverse of their load order, and Core's records last, because a
	 * module's records point at the ones loaded before them (ADMIN-3).
	 */
	@NamespaceAccessible
	public static void startRemoval() {
		removeFrom(installed().size() - 1);
	}

	/**
	 * Starts the removal of the module before the named one, or Core's own once none is left.
	 * Called by a module removal's own last stage, so Core does not need to know which modules
	 * exist.
	 */
	@NamespaceAccessible
	public static void removeAfter(String moduleName) {
		List<SampleDataModule> modules = installed();
		for (Integer index = 0; index < modules.size(); index++) {
			if (modules[index].moduleName() == moduleName) {
				removeFrom(index - 1);
				return;
			}
		}
	}

	private static void removeFrom(Integer index) {
		if (index < 0) {
			// Core's own records go last, through the Sample Data package that loaded them.
			SampleDataHost sampleHost = host();
			if (sampleHost != null) {
				SampleDataRemoveBatch.startRemoval(sampleHost.coreRemoveStages());
			}
			return;
		}
		installed()[index].enqueueRemove();
	}

	/** One count per installed module, for the status card. */
	@NamespaceAccessible
	public static List<ModuleCount> counts() {
		List<ModuleCount> counts = new List<ModuleCount>();
		for (SampleDataModule module : installed()) {
			ModuleCount count = new ModuleCount();
			count.name = module.moduleName();
			count.label = module.countLabel();
			count.recordCount = module.countLoaded();
			counts.add(count);
		}
		return counts;
	}

	/**
	 * True while any installed module still has sample records, for example ones its removal
	 * kept because the organization's own records point at them.
	 */
	@NamespaceAccessible
	public static Boolean anyHasSampleRecords() {
		for (SampleDataModule module : installed()) {
			if (module.hasSampleRecords() == true) {
				return true;
			}
		}
		return false;
	}

	/** Starts the module at this place in the load order, or ends the load when none is left. */
	private static void start(Integer index) {
		List<SampleDataModule> modules = installed();
		if (index >= modules.size()) {
			// The load has ended. Start the Rollup Queue for any totals of the people and gifts
			// it saved that are still pending; it starts nothing when none are (R-RQ3), and
			// there is none without the Rollup Builder module (ADR-0125).
			RollupEngineExtension engine = RollupEngineExtensions.find();
			if (engine != null) {
				engine.startQueuedRecalculation();
			}
			SampleDataHost sampleHost = host();
			if (sampleHost != null) {
				sampleHost.notifyLoadFinished();
			}
			return;
		}
		if (index < 0) {
			return;
		}
		modules[index].enqueueLoad();
	}

	/**
	 * One module class as an instance, or null when the package is not installed, the class
	 * is not reachable, or it does not implement the interface. A module that is not installed
	 * is not an error: an org without Giving is the ordinary case. One that cannot be built,
	 * or is the wrong shape, is logged, because it means a package shipped a broken module.
	 */
	@TestVisible
	private static SampleDataModule resolve(String className) {
		SampleDataModule module = (SampleDataModule) NamespaceUtil.build(
			className,
			SampleDataModule.class,
			'SampleDataModules.resolve'
		);
		// A module that ships its set as JSON has a static resource of that name instead
		// (D-200 S2), which Core loads itself.
		return module != null ? module : SampleDataFile.find(className);
	}
}
