/**
 * The code an admin copies so an org automation respects the BarnCRM Automation Control setting
 * (C-60, D-184). Framework free, so it ports to BarnCRM for WordPress (plan 9.9). The words
 * around each snippet are in the Core help catalog; only code is here.
 */

/** Which snippet a kind of automation takes: `flow`, `apex` or `formula`, or none. */
export function snippetKind(kind) {
  if (kind === 'Flow' || kind === 'ProcessBuilder') {
    return 'flow';
  }
  if (kind === 'ApexTrigger') {
    return 'apex';
  }
  if (kind === 'ValidationRule' || kind === 'WorkflowRule') {
    return 'formula';
  }
  return null;
}

/**
 * The code for a row. `classPrefix` is `ns.` or empty, `fieldPrefix` `ns__` or empty, as the
 * server gives them, so the code compiles in this org.
 */
export function snippetCode(row, classPrefix = '', fieldPrefix = '') {
  const kind = snippetKind(row && row.kind);
  if (kind === 'flow') {
    // The Automation Name the Check BarnCRM Automation action takes for the flow's own switch.
    return `Flow:${row.apiName}`;
  }
  if (kind === 'apex') {
    const action = `${classPrefix}CheckAutomationAction`;
    return [
      `${action}.Request ask = new ${action}.Request();`,
      `if (!${action}.check(new List<${action}.Request>{ ask })[0].run) {`,
      '    return;',
      '}'
    ].join('\n');
  }
  if (kind === 'formula') {
    const setting = `$Setup.${fieldPrefix}BarnCRM_Automation_Control__c`;
    return [
      'AND(',
      `    NOT(${setting}.${fieldPrefix}Pause_All__c),`,
      `    NOT(${setting}.${fieldPrefix}Bypass__c),`,
      '    /* the current formula */',
      ')'
    ].join('\n');
  }
  return '';
}
