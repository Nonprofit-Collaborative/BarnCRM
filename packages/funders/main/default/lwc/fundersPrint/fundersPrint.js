import { loadStyle } from 'lightning/platformResourceLoader';
import PRINT_CSS from '@salesforce/resourceUrl/BarnFunders_Print';

/**
 * Prints a Funders page (modules-5): loads the print stylesheet that hides the app chrome, then
 * opens the browser's print dialog. A stylesheet that cannot load still prints, with the chrome.
 *
 * @param {LightningElement} component the page component, which loadStyle needs
 */
export function printPage(component) {
  return loadStyle(component, PRINT_CSS)
    .catch(() => undefined)
    .then(() => {
      window.print();
    });
}
