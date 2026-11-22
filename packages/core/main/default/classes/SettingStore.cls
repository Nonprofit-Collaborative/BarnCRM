/**
 * The settings store (ADR-NEXT settings as custom metadata, D-219).
 *
 * A setting's default ships on its `Setting_Definition__mdt` row (`Default_Value__c`) and a value
 * the org changed is a `Setting_Value__mdt` record of the same name; both hold a JSON literal.
 * Both are read with `getAll()`, which costs no query, once per transaction (ADR-0094).
 *
 * A save is one metadata deployment of every changed value. It completes after this transaction,
 * so the values saved here are also kept for the rest of this transaction and read back first.
 * `SettingValueDeployCallback` audits the save and applies its side effects once it succeeds.
 *
 * The store names no settings object and no module (ADR-0059): `SettingsService` maps a Core key
 * to its definition, and a module's keys follow in phase 2.
 */
public without sharing class SettingStore {
	/** The hidden key that says the org's legacy custom setting values were carried over. */
	public static final String CARRIED_OVER = 'Settings_Carried_Over';

	public static final String ERROR_CONTEXT = 'BarnCRM Settings save';
	private static final String TYPE_NAME = 'Setting_Value';
	private static final String VALUE_FIELD = 'Value__c';
	public static final Integer VALUE_LIMIT = 255;
	private static final Integer LABEL_LIMIT = 40;

	public class SettingStoreException extends Exception {
	}

	/** One changed setting: its definition name, its audit name, old and new text, and its JSON. */
	public class Change {
		public String name;
		public String settingName;
		public String oldText;
		public String newText;
		public String json;
	}

	/** Starts a deployment. Tests cannot deploy metadata, so they get the in-memory one. */
	public interface Deployer {
		Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback);
	}

	private class PlatformDeployer implements Deployer {
		public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
			return Metadata.Operations.enqueueDeployment(container, callback);
		}
	}

	/**
	 * What a test gets instead of a deployment: the values are kept as deployed and the callback
	 * runs at once with a success, as the platform would run it once the deployment ended.
	 */
	@TestVisible
	private class InMemoryDeployer implements Deployer {
		public Id deploy(Metadata.DeployContainer container, Metadata.DeployCallback callback) {
			// As the platform: nothing deploys while the org is read only.
			if (System.getApplicationReadWriteMode() == ApplicationReadWriteMode.READ_ONLY) {
				throw new SettingStoreException('The org is read only.');
			}
			for (Metadata.Metadata item : container.getMetadata()) {
				Metadata.CustomMetadata record = (Metadata.CustomMetadata) item;
				Object value = record.values.isEmpty() ? null : record.values[0].value;
				deployedForTest.put(record.fullName.substringAfter('.'), value == null ? '' : String.valueOf(value));
			}
			Metadata.DeployResult result = new Metadata.DeployResult();
			result.status = Metadata.DeployStatus.Succeeded;
			callback.handleResult(result, null);
			return null;
		}
	}

	@TestVisible
	private static Deployer deployer = Test.isRunningTest() ? (Deployer) new InMemoryDeployer() : new PlatformDeployer();

	/** Values a test set, or the in-memory deployer kept, by definition name. */
	private static Map<String, String> deployedForTest = new Map<String, String>();
	/** Values saved in this transaction, by definition name, read ahead of everything else. */
	private static Map<String, String> pendingByName = new Map<String, String>();
	private static Map<String, String> savedByName;
	private static Map<String, Setting_Definition__mdt> definitionsByName;

	/**
	 * Every shipped definition by DeveloperName, from the platform's metadata cache. Always the
	 * shipped rows, never a test's stand-ins (SettingDefinitionSelector), because the defaults
	 * are what the packages ship.
	 */
	public static Map<String, Setting_Definition__mdt> definitions() {
		if (definitionsByName == null) {
			definitionsByName = new Map<String, Setting_Definition__mdt>(Setting_Definition__mdt.getAll());
		}
		return definitionsByName;
	}

	/** True when the org holds a value for this setting, even a blank one. */
	public static Boolean has(String name) {
		return pendingByName.containsKey(name) || deployedForTest.containsKey(name) || saved().containsKey(name);
	}

	/** The org's value as JSON text, or null when it holds none or a blank one. */
	public static String saved(String name) {
		String value = pendingByName.containsKey(name)
			? pendingByName.get(name)
			: deployedForTest.containsKey(name) ? deployedForTest.get(name) : saved().get(name);
		return String.isBlank(value) ? null : value;
	}

	/** The setting's value: the org's when it has one that parses, else the shipped default. */
	public static Object value(String name) {
		Object parsed = parse(saved(name));
		return parsed != null ? parsed : parse(defaultOf(name));
	}

	/** The shipped default as JSON text, or null. */
	public static String defaultOf(String name) {
		Setting_Definition__mdt definition = definitions().get(name);
		return definition == null || String.isBlank(definition.Default_Value__c) ? null : definition.Default_Value__c;
	}

	/** True once the legacy custom setting values have been carried over (R-SV1). */
	public static Boolean isCarriedOver() {
		return parse(saved(CARRIED_OVER)) == true;
	}

	/**
	 * A JSON literal as a value: Boolean, Integer, Long, Decimal or String, or null when the text
	 * is blank or not JSON (an edit made in Setup that does not parse falls back to the default).
	 */
	public static Object parse(String literal) {
		if (String.isBlank(literal)) {
			return null;
		}
		try {
			// Wrapped, so a bare literal parses whatever the platform's top-level rules are.
			return ((Map<String, Object>) JSON.deserializeUntyped('{"v":' + literal + '}')).get('v');
		} catch (Exception notJson) {
			return null;
		}
	}

	/** A value as the JSON literal the store holds; blank for null. */
	public static String toJson(Object value) {
		return value == null ? '' : JSON.serialize(value);
	}

	/**
	 * Saves the changes in one deployment and returns its Id (null in a test). Refused, with
	 * nothing saved, when a value is longer than the store holds or Salesforce does not accept
	 * the deployment (on a packaged install, until the Setup switch is on: ADR-NEXT decision 5).
	 */
	public static Id save(List<Change> changes, Boolean audit) {
		if (changes == null || changes.isEmpty()) {
			return null;
		}
		Metadata.DeployContainer container = new Metadata.DeployContainer();
		for (Change change : changes) {
			String json = change.json == null ? '' : change.json;
			if (json.length() > VALUE_LIMIT) {
				throw new SettingStoreException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
			}
			container.addMetadata(record(change.name, json));
		}
		Id deploymentId;
		try {
			deploymentId = deployer.deploy(
				container,
				new SettingValueDeployCallback(changes, audit, UserInfo.getUserId())
			);
		} catch (Exception refused) {
			ErrorLogger.log(refused, ERROR_CONTEXT);
			throw new SettingStoreException(BarnHelp.text('Core', 'Core_CmdtManager_DeployRefused'));
		}
		for (Change change : changes) {
			pendingByName.put(change.name, change.json == null ? '' : change.json);
		}
		return deploymentId;
	}

	private static Metadata.CustomMetadata record(String name, String json) {
		Metadata.CustomMetadata record = new Metadata.CustomMetadata();
		record.fullName = NamespaceUtil.prefix() + TYPE_NAME + '.' + name;
		record.label = name.replace('_', ' ').left(LABEL_LIMIT);
		record.protected_x = false;
		Metadata.CustomMetadataValue value = new Metadata.CustomMetadataValue();
		value.field = NamespaceUtil.qualify(VALUE_FIELD);
		value.value = String.isBlank(json) ? null : json;
		record.values.add(value);
		return record;
	}

	/** Puts a value in the store for a test, as if it were deployed. Does nothing outside a test. */
	public static void setForTest(String name, Object value) {
		if (Test.isRunningTest()) {
			deployedForTest.put(name, toJson(value));
			pendingByName.remove(name);
		}
	}

	/** Forgets every value a test saved or put in the store, as if the org had saved none. */
	public static void resetForTest() {
		if (Test.isRunningTest()) {
			deployedForTest.clear();
			pendingByName.clear();
			clearCache();
		}
	}

	/** True when the org holds at least one Setting Value, this transaction's saves included. */
	public static Boolean hasAnyValue() {
		return !pendingByName.isEmpty() || !deployedForTest.isEmpty() || !saved().isEmpty();
	}

	/** Forgets what was read, so the next read comes from the platform; keeps this transaction's saves. */
	public static void clearCache() {
		savedByName = null;
		definitionsByName = null;
	}

	private static Map<String, String> saved() {
		if (savedByName == null) {
			savedByName = new Map<String, String>();
			for (Setting_Value__mdt row : Setting_Value__mdt.getAll().values()) {
				savedByName.put(row.DeveloperName, row.Value__c);
			}
		}
		return savedByName;
	}
}
