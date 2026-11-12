/**
 * The Component property of BarnCRM Built Component in Lightning App Builder (LB-02; ADR-NEXT
 * `NEXT-lwc-builder-module.md`, decision 4): every built component the admin can read, by name,
 * storing its key, so a page keeps finding it after the component is moved to another org.
 */
public with sharing class LwcBuilderComponentPicklist extends VisualEditor.DynamicPickList {
	private List<VisualEditor.DataRow> rows;

	public override VisualEditor.DataRow getDefaultValue() {
		List<VisualEditor.DataRow> all = rows();
		return all.isEmpty() ? null : all[0];
	}

	public override VisualEditor.DynamicPickListRows getValues() {
		VisualEditor.DynamicPickListRows values = new VisualEditor.DynamicPickListRows();
		for (VisualEditor.DataRow row : rows()) {
			values.addRow(row);
		}
		return values;
	}

	private List<VisualEditor.DataRow> rows() {
		if (rows == null) {
			rows = new List<VisualEditor.DataRow>();
			for (Built_Component__c component : [
				SELECT Name, Key__c
				FROM Built_Component__c
				WITH USER_MODE
				ORDER BY Name
				LIMIT 500
			]) {
				rows.add(new VisualEditor.DataRow(component.Name, component.Key__c));
			}
		}
		return rows;
	}
}
