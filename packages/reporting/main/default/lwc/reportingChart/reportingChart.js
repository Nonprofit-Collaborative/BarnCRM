import { LightningElement, api } from 'lwc';

const EMPTY = {
  viewBox: '0 0 640 320',
  lines: [],
  rects: [],
  paths: [],
  circles: [],
  texts: [],
  legend: []
};

/**
 * Draws one Advanced Reporting chart from the shapes c/reportingChartModel worked out: an SVG
 * that scales to its width, a title on every bar, slice and point for hover, and a legend when
 * there is more than one series. The chart is one image to a screen reader, named by `summary`;
 * the table beside it (Show Table) carries the numbers.
 */
export default class ReportingChart extends LightningElement {
  /** The chart model (`chartModel` in c/reportingChartModel). */
  @api chart = EMPTY;

  /** What the chart shows, in words, for screen readers. */
  @api summary = '';

  get hasLegend() {
    return !!(this.chart && this.chart.legend && this.chart.legend.length);
  }
}
