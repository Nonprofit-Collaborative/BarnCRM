/**
 * Programs' own step after each pass of Core's access sync (ADR-0151 decision 7, D-200 S1): the
 * Participant Privacy group follows its preset (P-08), repairing a hand change. Registered in the
 * Programs catalog row as `ModuleAccessStep: ProgramsAccessStep`; Core builds it by name, so it
 * needs a public constructor.
 */
@NamespaceAccessible
public with sharing class ProgramsAccessStep implements ModuleAccessStep {
	@NamespaceAccessible
	public ProgramsAccessStep() {
		// Built by name from Core (ModuleExtensions).
	}

	public void afterSync() {
		ProgramsSharing.applyPreset();
	}
}
