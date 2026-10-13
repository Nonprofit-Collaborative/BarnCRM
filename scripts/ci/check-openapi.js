#!/usr/bin/env node
/**
 * Checks the published OpenAPI document for the inbound gift API
 * (docs/architecture/reference/inbound-gift-api.openapi.yaml) on every pull request.
 *
 * Two things break without it. First, the file is only ever read by integrators' tools, never
 * by the build, so a YAML slip or a dangling $ref would ship and be found by a partner. Second,
 * the document is a hand-written copy of the Apex contract (InboundGift, InboundGiftResult,
 * InboundGiftRequest), and a field or error code added to the Apex and not to the document
 * makes the published contract wrong without anything failing.
 *
 * Checks, all offline:
 * 1. The file parses as YAML, strictly (duplicate keys fail).
 * 2. It declares OpenAPI 3.1.x, has info.title, info.version and at least one path.
 * 3. Every local $ref resolves, every operation has a unique operationId, and every response
 *    has a description (both required by the specification).
 * 4. The request schema's properties are exactly InboundGift's global fields, and its
 *    required list is exactly the fields marked required=true; the result schema's
 *    properties are exactly InboundGiftResult's global fields; the outcome and errorCode
 *    enums are exactly the OUTCOME_ and ERROR_ constants; the two maxLength values match
 *    InboundGiftRequest's limits.
 *
 * It is not a full OpenAPI validator: those need a network install, and the defects above
 * are the ones this document can actually have. Exit code 1 on any finding.
 */

const fs = require('fs');
const path = require('path');
const YAML = require('yaml');

const ROOT = path.resolve(__dirname, '..', '..');
const DOC = path.join(ROOT, 'docs', 'architecture', 'reference', 'inbound-gift-api.openapi.yaml');
const CLASSES = path.join(ROOT, 'packages', 'connect', 'main', 'default', 'classes');
const HTTP_METHODS = ['get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'];

const findings = [];

function apex(name) {
  return fs.readFileSync(path.join(CLASSES, name + '.cls'), 'utf8');
}

function globalFields(source) {
  const names = [];
  const pattern = /^\s*global\s+(?!static|class|with|without|inherited)[\w<>, ]+?\s+(\w+)\s*;/gm;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    names.push(match[1]);
  }
  return names;
}

function requiredFields(source) {
  const names = [];
  // Lazy up to the first ") global <type> <name>;", so parentheses inside a description are fine.
  const pattern = /@InvocableVariable\(([\s\S]*?)\)\s*global\s+[\w<>]+\s+(\w+)\s*;/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    if (/required\s*=\s*true/.test(match[1])) {
      names.push(match[2]);
    }
  }
  return names;
}

function constants(source, prefix) {
  const values = [];
  const pattern = new RegExp(`static\\s+final\\s+String\\s+${prefix}\\w+\\s*=\\s*'([^']*)'`, 'g');
  let match;
  while ((match = pattern.exec(source)) !== null) {
    values.push(match[1]);
  }
  return values;
}

function integerConstant(source, name) {
  const match = new RegExp(`Integer\\s+${name}\\s*=\\s*(\\d+)`).exec(source);
  return match ? Number(match[1]) : null;
}

function sameSet(label, documented, code) {
  const doc = [...new Set(documented || [])].sort();
  const apexValues = [...new Set(code)].sort();
  const missing = apexValues.filter((v) => !doc.includes(v));
  const extra = doc.filter((v) => !apexValues.includes(v));
  if (apexValues.length === 0) {
    findings.push(`${label}: nothing found in the Apex, so the comparison cannot run`);
  }
  if (missing.length) {
    findings.push(`${label}: in the Apex but not the document: ${missing.join(', ')}`);
  }
  if (extra.length) {
    findings.push(`${label}: in the document but not the Apex: ${extra.join(', ')}`);
  }
}

function resolveRef(doc, ref) {
  if (!ref.startsWith('#/')) {
    return true;
  }
  let node = doc;
  for (const part of ref.slice(2).split('/')) {
    const key = part.replace(/~1/g, '/').replace(/~0/g, '~');
    if (node === null || typeof node !== 'object' || !(key in node)) {
      return false;
    }
    node = node[key];
  }
  return true;
}

function walkRefs(doc, node, where) {
  if (Array.isArray(node)) {
    node.forEach((item, index) => walkRefs(doc, item, `${where}[${index}]`));
    return;
  }
  if (node === null || typeof node !== 'object') {
    return;
  }
  for (const [key, value] of Object.entries(node)) {
    if (key === '$ref' && typeof value === 'string' && !resolveRef(doc, value)) {
      findings.push(`${where}: $ref ${value} does not resolve`);
    }
    walkRefs(doc, value, `${where}.${key}`);
  }
}

function checkStructure(doc) {
  if (!/^3\.1\.\d+$/.test(String(doc.openapi))) {
    findings.push(`openapi is ${doc.openapi}, expected 3.1.x`);
  }
  if (!doc.info || !doc.info.title || !doc.info.version) {
    findings.push('info.title and info.version are required');
  }
  const paths = doc.paths || {};
  if (Object.keys(paths).length === 0) {
    findings.push('no paths');
  }
  const operationIds = new Set();
  for (const [route, item] of Object.entries(paths)) {
    for (const method of HTTP_METHODS) {
      const operation = item[method];
      if (!operation) {
        continue;
      }
      const where = `${method.toUpperCase()} ${route}`;
      if (!operation.operationId) {
        findings.push(`${where}: no operationId`);
      } else if (operationIds.has(operation.operationId)) {
        findings.push(`${where}: operationId ${operation.operationId} is used twice`);
      } else {
        operationIds.add(operation.operationId);
      }
      for (const [status, response] of Object.entries(operation.responses || {})) {
        if (!response || !response.description) {
          findings.push(`${where} ${status}: response has no description`);
        }
      }
    }
  }
  walkRefs(doc, doc, '#');
}

function checkAgainstApex(doc) {
  const schemas = (doc.components && doc.components.schemas) || {};
  const gift = schemas.InboundGift || {};
  const result = schemas.InboundGiftResult || {};
  const giftSource = apex('InboundGift');
  const resultSource = apex('InboundGiftResult');
  const requestSource = apex('InboundGiftRequest');

  sameSet('InboundGift properties', Object.keys(gift.properties || {}), globalFields(giftSource));
  sameSet('InboundGift required', gift.required, requiredFields(giftSource));
  sameSet(
    'InboundGiftResult properties',
    Object.keys(result.properties || {}),
    globalFields(resultSource)
  );
  const resultProperties = result.properties || {};
  sameSet(
    'outcome enum',
    resultProperties.outcome && resultProperties.outcome.enum,
    constants(resultSource, 'OUTCOME_')
  );
  sameSet(
    'errorCode enum',
    resultProperties.errorCode && resultProperties.errorCode.enum,
    constants(resultSource, 'ERROR_')
  );

  const limits = [
    ['externalId', 'MAX_EXTERNAL_ID'],
    ['paymentReference', 'MAX_PAYMENT_REFERENCE']
  ];
  for (const [property, constant] of limits) {
    const documented =
      gift.properties && gift.properties[property] && gift.properties[property].maxLength;
    const code = integerConstant(requestSource, constant);
    if (documented !== code) {
      findings.push(
        `${property} maxLength is ${documented}, InboundGiftRequest.${constant} is ${code}`
      );
    }
  }
}

function main() {
  let doc;
  try {
    doc = YAML.parse(fs.readFileSync(DOC, 'utf8'), {
      strict: true,
      uniqueKeys: true,
      prettyErrors: true
    });
  } catch (error) {
    console.log(
      `OpenAPI check failed: ${path.relative(ROOT, DOC)} does not parse:\n${error.message}`
    );
    return 1;
  }
  if (doc === null || typeof doc !== 'object') {
    console.log('OpenAPI check failed: the document is empty');
    return 1;
  }
  checkStructure(doc);
  checkAgainstApex(doc);
  if (findings.length) {
    console.log('OpenAPI check failed:');
    for (const finding of findings) {
      console.log(`  ${finding}`);
    }
    return 1;
  }
  console.log(`OpenAPI check passed: ${path.relative(ROOT, DOC)}`);
  return 0;
}

process.exitCode = main();
