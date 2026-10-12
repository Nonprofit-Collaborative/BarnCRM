/**
 * Thrown by the sample data loader (C-10) when sample data cannot be loaded, removed, or
 * is already present. Always caught, logged through ErrorLogger, and rethrown so the
 * caller (SampleDataController) can surface a clear message to the LWC.
 */
public with sharing class SampleDataException extends Exception {
}
