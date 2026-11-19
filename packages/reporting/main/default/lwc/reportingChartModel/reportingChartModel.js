/**
 * Advanced Reporting's chart geometry (ADR-0231 advanced reporting): bar, column, line and
 * donut charts as plain shapes in an SVG view box (rectangles, paths, circles, lines and text
 * with their positions worked out here), so the component only draws them and the same charts
 * draw anywhere an SVG does. The view box scales to the width it is given, so a chart fits a
 * phone and a wide dashboard alike.
 *
 * Framework free (plan 9.9). Words come from the caller: `format(value, measureIndex)` writes a
 * value, `words.other` names the slice that gathers the smallest donut slices.
 */

export const TONES = 8;
export const MAX_CATEGORIES = 25;
export const MAX_SLICES = 10;

const WIDTH = 640;
const round = (value) => Math.round(value * 10) / 10;
const truncate = (text, size) => {
  const value = String(text === null || text === undefined ? '' : text);
  return value.length > size ? value.slice(0, Math.max(1, size - 1)) + '…' : value;
};

/** A step of 1, 2 or 5 times a power of ten that splits the span into about five ticks. */
export function niceStep(span) {
  if (!(span > 0)) {
    return 1;
  }
  const rough = span / 5;
  const power = Math.pow(10, Math.floor(Math.log10(rough)));
  const scaled = rough / power;
  const factor = scaled <= 1 ? 1 : scaled <= 2 ? 2 : scaled <= 5 ? 5 : 10;
  return factor * power;
}

/** The axis from the lowest to the highest value, zero always on it, in nice steps. */
export function niceScale(values) {
  const finite = values.filter((value) => Number.isFinite(value));
  const low = Math.min(0, ...finite);
  const high = Math.max(0, ...finite);
  const step = niceStep(high - low || 1);
  const min = Math.floor(low / step) * step;
  const max = Math.ceil(high / step) * step || step;
  const ticks = [];
  for (let tick = min; tick <= max + step / 2; tick += step) {
    ticks.push(round(tick * 1e6) / 1e6);
  }
  return { min, max, ticks };
}

/**
 * The categories (first grouping) and series (second grouping, else each total) of arranged
 * groups, with the value of each category in each series.
 */
export function seriesOf(report, arranged) {
  const twoGroups = report.groups.length > 1;
  const categories = [];
  const categoryIndex = new Map();
  const series = [];
  const seriesIndex = new Map();
  const cells = new Map();
  const addSeries = (key, label) => {
    if (!seriesIndex.has(key)) {
      seriesIndex.set(key, series.length);
      series.push({ key: `s${series.length}`, label });
    }
    return seriesIndex.get(key);
  };
  if (!twoGroups) {
    report.measures.forEach((measure, index) => addSeries(`m${index}`, measure.label));
  }
  for (const item of arranged.items) {
    const first = String(item.keys[0]);
    if (!categoryIndex.has(first)) {
      categoryIndex.set(first, categories.length);
      categories.push({ key: `c${categories.length}`, label: item.texts[0] });
    }
    const c = categoryIndex.get(first);
    if (twoGroups) {
      const s = addSeries(String(item.keys[1]), item.texts[1]);
      cells.set(`${c}:${s}`, Number(item.values[0]) || 0);
    } else {
      item.values.forEach((value, s) => cells.set(`${c}:${s}`, Number(value) || 0));
    }
  }
  const shown = categories.slice(0, MAX_CATEGORIES);
  const values = shown.map((category, c) => series.map((unused, s) => cells.get(`${c}:${s}`) || 0));
  return {
    categories: shown,
    series,
    values,
    measureIndex: (s) => (twoGroups ? 0 : s),
    cut: categories.length > shown.length
  };
}

function legendOf(series) {
  return series.length > 1
    ? series.map((entry, index) => ({
        key: entry.key,
        label: entry.label,
        swatch: `swatch tone${index % TONES}`
      }))
    : [];
}

/** Totals of each category across series, for a stacked chart's axis. */
function stackedTotals(values) {
  return values.flatMap((row) => {
    let up = 0;
    let down = 0;
    for (const value of row) {
      if (value >= 0) {
        up += value;
      } else {
        down += value;
      }
    }
    return [up, down];
  });
}

/** A column or line chart: categories across, values up. */
function verticalChart(report, data, format) {
  const stacked = report.view.stacked && data.series.length > 1 && report.view.type === 'column';
  const isLine = report.view.type === 'line';
  const height = 320;
  const left = 72;
  const right = 16;
  const top = 16;
  const bottom = 56;
  const plotWidth = WIDTH - left - right;
  const plotHeight = height - top - bottom;
  const scale = niceScale(stacked ? stackedTotals(data.values) : data.values.flat());
  const y = (value) => round(top + (plotHeight * (scale.max - value)) / (scale.max - scale.min));
  const band = plotWidth / Math.max(1, data.categories.length);
  const shapes = { rects: [], paths: [], circles: [], lines: [], texts: [] };
  scale.ticks.forEach((tick, index) => {
    shapes.lines.push({
      key: `t${index}`,
      x1: left,
      x2: WIDTH - right,
      y1: y(tick),
      y2: y(tick),
      css: tick === 0 ? 'axis' : 'grid'
    });
    shapes.texts.push({
      key: `tl${index}`,
      x: left - 8,
      y: y(tick) + 4,
      anchor: 'end',
      css: 'tick',
      text: format(tick, 0)
    });
  });
  const every = Math.ceil(data.categories.length / 12);
  const labelSize = Math.max(3, Math.floor((band * every) / 7));
  data.categories.forEach((category, c) => {
    const center = left + band * c + band / 2;
    if (c % every === 0) {
      shapes.texts.push({
        key: `cl${c}`,
        x: round(center),
        y: height - bottom + 18,
        anchor: 'middle',
        css: 'category',
        text: truncate(category.label, labelSize)
      });
    }
    if (isLine) {
      return;
    }
    const inner = band * 0.7;
    let up = 0;
    let down = 0;
    data.series.forEach((entry, s) => {
      const value = data.values[c][s];
      const width = stacked ? inner : inner / data.series.length;
      const x = left + band * c + band * 0.15 + (stacked ? 0 : width * s);
      let from = 0;
      if (stacked) {
        from = value >= 0 ? up : down;
        if (value >= 0) {
          up += value;
        } else {
          down += value;
        }
      }
      const y1 = y(from + value);
      const y0 = y(from);
      shapes.rects.push({
        key: `r${c}_${s}`,
        x: round(x),
        y: Math.min(y0, y1),
        width: round(Math.max(1, width - 1)),
        height: round(Math.max(Math.abs(y0 - y1), value === 0 ? 0 : 1)),
        css: `mark tone${s % TONES}`,
        title: `${category.label}${data.series.length > 1 ? ', ' + entry.label : ''}: ${format(value, data.measureIndex(s))}`
      });
    });
  });
  if (isLine) {
    data.series.forEach((entry, s) => {
      const points = data.categories.map((category, c) => ({
        x: round(left + band * c + band / 2),
        y: y(data.values[c][s]),
        title: `${category.label}${data.series.length > 1 ? ', ' + entry.label : ''}: ${format(data.values[c][s], data.measureIndex(s))}`
      }));
      shapes.paths.push({
        key: `l${s}`,
        d: points.map((point, index) => `${index ? 'L' : 'M'}${point.x} ${point.y}`).join(' '),
        css: `line stroke${s % TONES}`,
        title: entry.label
      });
      points.forEach((point, c) =>
        shapes.circles.push({
          key: `p${s}_${c}`,
          cx: point.x,
          cy: point.y,
          r: 4,
          css: `mark tone${s % TONES}`,
          title: point.title
        })
      );
    });
  }
  return { viewBox: `0 0 ${WIDTH} ${height}`, ...shapes };
}

/** A bar chart: categories down the side, values across, room for long names. */
function horizontalChart(report, data, format) {
  const stacked = report.view.stacked && data.series.length > 1;
  const row = Math.max(20, 12 * (stacked ? 1 : data.series.length) + 12);
  const left = 168;
  const right = 72;
  const top = 8;
  const bottom = 28;
  const height = top + bottom + row * Math.max(1, data.categories.length);
  const plotWidth = WIDTH - left - right;
  const scale = niceScale(stacked ? stackedTotals(data.values) : data.values.flat());
  const x = (value) => round(left + (plotWidth * (value - scale.min)) / (scale.max - scale.min));
  const shapes = { rects: [], paths: [], circles: [], lines: [], texts: [] };
  scale.ticks.forEach((tick, index) => {
    shapes.lines.push({
      key: `t${index}`,
      x1: x(tick),
      x2: x(tick),
      y1: top,
      y2: height - bottom,
      css: tick === 0 ? 'axis' : 'grid'
    });
    shapes.texts.push({
      key: `tl${index}`,
      x: x(tick),
      y: height - bottom + 16,
      anchor: 'middle',
      css: 'tick',
      text: format(tick, 0)
    });
  });
  data.categories.forEach((category, c) => {
    const rowTop = top + row * c;
    shapes.texts.push({
      key: `cl${c}`,
      x: left - 8,
      y: round(rowTop + row / 2 + 4),
      anchor: 'end',
      css: 'category',
      text: truncate(category.label, 24)
    });
    const inner = row - 8;
    const thickness = stacked ? inner : inner / data.series.length;
    let up = 0;
    let down = 0;
    data.series.forEach((entry, s) => {
      const value = data.values[c][s];
      let from = 0;
      if (stacked) {
        from = value >= 0 ? up : down;
        if (value >= 0) {
          up += value;
        } else {
          down += value;
        }
      }
      const x0 = x(from);
      const x1 = x(from + value);
      const yTop = round(rowTop + 4 + (stacked ? 0 : thickness * s));
      shapes.rects.push({
        key: `r${c}_${s}`,
        x: Math.min(x0, x1),
        y: yTop,
        width: round(Math.max(Math.abs(x1 - x0), value === 0 ? 0 : 1)),
        height: round(Math.max(1, thickness - 1)),
        css: `mark tone${s % TONES}`,
        title: `${category.label}${data.series.length > 1 ? ', ' + entry.label : ''}: ${format(value, data.measureIndex(s))}`
      });
      if (!stacked && data.series.length === 1) {
        shapes.texts.push({
          key: `v${c}`,
          x: round(Math.max(x0, x1) + 6),
          y: round(yTop + thickness / 2 + 3),
          anchor: 'start',
          css: 'value',
          text: format(value, data.measureIndex(s))
        });
      }
    });
    if (stacked) {
      shapes.texts.push({
        key: `v${c}`,
        x: round(x(up) + 6),
        y: round(rowTop + row / 2 + 4),
        anchor: 'start',
        css: 'value',
        text: format(up + down, 0)
      });
    }
  });
  return { viewBox: `0 0 ${WIDTH} ${height}`, ...shapes };
}

function arc(cx, cy, radius, angle) {
  return [round(cx + radius * Math.sin(angle)), round(cy - radius * Math.cos(angle))];
}

/** A donut: the first total of each category as a share of the whole, the total in the middle. */
function donutChart(report, data, format, words) {
  const entries = data.categories
    .map((category, c) => ({ label: category.label, value: data.values[c][0] }))
    .filter((entry) => entry.value > 0)
    .sort((left, right) => right.value - left.value);
  const slices = entries.slice(0, MAX_SLICES);
  const rest = entries.slice(MAX_SLICES).reduce((sum, entry) => sum + entry.value, 0);
  if (rest > 0) {
    slices.push({ label: words.other || '', value: rest });
  }
  const total = slices.reduce((sum, entry) => sum + entry.value, 0);
  const cx = 160;
  const cy = 160;
  const outer = 150;
  const inner = 92;
  const paths = [];
  let angle = 0;
  slices.forEach((slice, index) => {
    const sweep = total ? (2 * Math.PI * slice.value) / total : 0;
    const end = Math.min(angle + sweep, angle + 2 * Math.PI - 0.0001);
    const large = end - angle > Math.PI ? 1 : 0;
    const [ox0, oy0] = arc(cx, cy, outer, angle);
    const [ox1, oy1] = arc(cx, cy, outer, end);
    const [ix1, iy1] = arc(cx, cy, inner, end);
    const [ix0, iy0] = arc(cx, cy, inner, angle);
    paths.push({
      key: `d${index}`,
      d: `M${ox0} ${oy0} A${outer} ${outer} 0 ${large} 1 ${ox1} ${oy1} L${ix1} ${iy1} A${inner} ${inner} 0 ${large} 0 ${ix0} ${iy0} Z`,
      css: `mark tone${index % TONES}`,
      title: `${slice.label}: ${format(slice.value, 0)} (${Math.round((100 * slice.value) / (total || 1))}%)`
    });
    angle += sweep;
  });
  return {
    viewBox: '0 0 320 320',
    rects: [],
    paths,
    circles: [],
    lines: [],
    texts: [
      { key: 'total', x: cx, y: cy + 8, anchor: 'middle', css: 'total', text: format(total, 0) }
    ],
    legend: slices.map((slice, index) => ({
      key: `k${index}`,
      label: `${slice.label}: ${format(slice.value, 0)} (${Math.round((100 * slice.value) / (total || 1))}%)`,
      swatch: `swatch tone${index % TONES}`
    }))
  };
}

/**
 * The chart for a totals report: `{ kind, viewBox, rects, paths, circles, lines, texts,
 * legend, summary, cut }`, or `{ kind: 'metric', value }` for a metric tile. `summary` says in
 * words what the chart shows, for screen readers.
 */
export function chartModel(report, arranged, format, words = {}) {
  const type = report.view.type;
  if (type === 'metric') {
    const first = arranged.items[0];
    return {
      kind: 'metric',
      value: first ? first.values[0] : null,
      label: report.measures.length ? report.measures[0].label : ''
    };
  }
  const data = seriesOf(report, arranged);
  let shapes;
  if (type === 'donut') {
    shapes = donutChart(report, data, format, words);
  } else if (type === 'bar') {
    shapes = horizontalChart(report, data, format);
  } else {
    shapes = verticalChart(report, data, format);
  }
  const largest = data.categories
    .map((category, c) => ({ label: category.label, value: data.values[c][0] }))
    .sort((left, right) => right.value - left.value)[0];
  return {
    kind: type,
    legend: shapes.legend || legendOf(data.series),
    ...shapes,
    cut: data.cut,
    categories: data.categories.length,
    largest: largest ? `${largest.label}: ${format(largest.value, 0)}` : ''
  };
}
