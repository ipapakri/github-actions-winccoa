#!/usr/bin/env node
/**
 * Build OK/NOK summary from classic WinCC OA logs via npm-winccoa-log-reader.
 *
 * Env:
 *   LOG_PATH, SUMMARY_PATH, SEVERITIES, INCLUDE_ERROR_TYPES,
 *   PATH_STRIP_PREFIXES, REPORT_TITLE, COMMENT_MARKER, GITHUB_WORKSPACE
 */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

function splitCsv(raw) {
  return String(raw || '')
    .split(/[,\n]/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function loadReader(pkgRoot) {
  const cjs = path.join(pkgRoot, 'dist', 'cjs', 'index.js');
  const esm = path.join(pkgRoot, 'dist', 'esm', 'index.js');
  if (fs.existsSync(cjs)) {
    return require(cjs);
  }
  if (fs.existsSync(esm)) {
    return require(esm);
  }
  throw new Error(`Could not load log-reader from ${pkgRoot}`);
}

function normalizePath(raw, stripPrefixes) {
  if (!raw) return null;
  let p = String(raw).trim().replace(/\\/g, '/');
  p = p.replace(/^\.\//, '');
  for (const prefix of stripPrefixes) {
    const pref = prefix.replace(/\\/g, '/');
    if (pref && (p === pref.replace(/\/$/, '') || p.startsWith(pref))) {
      p = p.startsWith(pref) ? p.slice(pref.length) : '';
      break;
    }
  }
  const ws = (process.env.GITHUB_WORKSPACE || '').replace(/\\/g, '/');
  if (ws && (p === ws || p.startsWith(ws + '/'))) {
    p = p === ws ? '' : p.slice(ws.length + 1);
  }
  p = p.replace(/^\/+/, '');
  return p || null;
}

/**
 * PARAM INFO paths are often project-relative (libs/foo.ctl), while Script/
 * Library metadata is often workspace-absolute after strip
 * (src/Squirt/scripts/libs/foo.ctl). Treat suffix matches as the same file.
 */
function pathsReferToSameFile(a, b) {
  if (!a || !b) return false;
  if (a === b) return true;
  if (a.endsWith('/' + b) || b.endsWith('/' + a)) return true;
  const ba = a.split('/').slice(-2).join('/');
  const bb = b.split('/').slice(-2).join('/');
  return ba.length > 0 && ba === bb && a.includes(ba) && b.includes(bb);
}

function preferDisplayPath(a, b) {
  if (!a) return b;
  if (!b) return a;
  return a.length >= b.length ? a : b;
}

function locationFromEntry(entry) {
  const md = entry.metadata || {};
  const file = md.script || md.library || null;
  const line = typeof md.line === 'number' ? md.line : null;
  return { file, line };
}

function isFinding(entry, severities, includeTypes) {
  const prio = String(entry.errorPriority || '').toUpperCase();
  if (!severities.includes(prio)) return false;
  if (includeTypes.length > 0) {
    const t = String(entry.errorType || '').toUpperCase();
    if (!includeTypes.includes(t)) return false;
  }
  return true;
}

function extractCheckedFiles(entries, stripPrefixes) {
  const files = new Set();
  for (const e of entries) {
    if (
      String(e.errorType || '').toUpperCase() === 'PARAM' &&
      String(e.errorPriority || '').toUpperCase() === 'INFO' &&
      e.errorText
    ) {
      const t = String(e.errorText).trim();
      if (!/^[A-Za-z0-9_./\\-]+\.(ctl|pnl|xml|ctc)$/i.test(t)) {
        continue;
      }
      const n = normalizePath(t, stripPrefixes);
      if (n) files.add(n);
    }
  }
  return files;
}

function main() {
  const logPath = process.env.LOG_PATH;
  const summaryPath =
    process.env.SUMMARY_PATH || '.artifacts/winccoa-log-report.json';
  const pkgRoot = process.env.LOG_READER_PKG_ROOT;
  const title = process.env.REPORT_TITLE || 'WinCC OA log report';
  const marker =
    process.env.COMMENT_MARKER || '<!-- winccoa-logs-to-pr-review -->';

  if (!logPath || !fs.existsSync(logPath)) {
    console.error(`::error::Log file not found: ${logPath}`);
    process.exit(2);
  }
  if (!pkgRoot) {
    console.error('::error::LOG_READER_PKG_ROOT is required');
    process.exit(2);
  }

  const severities = splitCsv(
    process.env.SEVERITIES || 'WARNING,SEVERE,FATAL',
  ).map((s) => s.toUpperCase());
  const includeTypes = splitCsv(process.env.INCLUDE_ERROR_TYPES || '').map(
    (s) => s.toUpperCase(),
  );
  const stripPrefixes = splitCsv(
    process.env.PATH_STRIP_PREFIXES || '/workspace/',
  ).map((s) => (s.endsWith('/') || s.length === 0 ? s : `${s}/`));

  const { readLogFile, parseLogContent } = loadReader(pkgRoot);
  const content = fs.readFileSync(logPath, 'utf8');
  const allEntries = parseLogContent
    ? parseLogContent(content, path.basename(logPath))
    : readLogFile({ filePath: logPath });

  const checkedFromParam = extractCheckedFiles(allEntries, stripPrefixes);

  const findings = [];
  /** @type {Map<string, string>} matchKey -> display path */
  const nokDisplay = new Map();

  for (const entry of allEntries) {
    if (!isFinding(entry, severities, includeTypes)) continue;
    const loc = locationFromEntry(entry);
    let file = normalizePath(loc.file, stripPrefixes);
    if (!file && entry.errorText) {
      const m = String(entry.errorText).match(
        /((?:\/|\w:)?[^\s,]+\.(?:ctl|pnl|xml))/i,
      );
      if (m) file = normalizePath(m[1], stripPrefixes);
    }
    if (!file) {
      file = '(no-file)';
    }

    let display = file;
    let key = file;
    if (file !== '(no-file)') {
      for (const checked of checkedFromParam) {
        if (pathsReferToSameFile(file, checked)) {
          key = checked;
          display = preferDisplayPath(file, checked);
          break;
        }
      }
    }

    const line = loc.line || null;
    findings.push({
      file: display,
      matchKey: key,
      line,
      severity: entry.errorPriority,
      errorType: entry.errorType,
      errorCode: entry.errorCode ?? null,
      errorCatalog: entry.errorCatalog ?? null,
      message: String(entry.errorText || '').split('\n')[0].trim(),
      raw: (entry.rawLines || []).join('\n'),
    });

    const prev = nokDisplay.get(key);
    nokDisplay.set(key, preferDisplayPath(prev, display));
  }

  const nokKeys = [...nokDisplay.keys()];
  const okFiles = [...checkedFromParam]
    .filter((f) => !nokKeys.some((k) => pathsReferToSameFile(f, k)))
    .sort();

  const nokList = [...nokDisplay.entries()]
    .filter(([k]) => k !== '(no-file)')
    .map(([, display]) => display)
    .sort();
  const systemNok = nokDisplay.has('(no-file)');

  const checkedCount = okFiles.length + nokList.length + (systemNok ? 1 : 0);

  const summary = {
    title,
    marker,
    logPath,
    generatedAt: new Date().toISOString(),
    counts: {
      checked: checkedCount,
      ok: okFiles.length,
      nok: nokList.length + (systemNok ? 1 : 0),
      findings: findings.length,
      paramInfoFiles: checkedFromParam.size,
    },
    okFiles,
    nokFiles: systemNok ? [...nokList, '(no-file)'] : nokList,
    findings: findings.map(({ matchKey, ...rest }) => rest),
    filters: {
      severities,
      includeErrorTypes: includeTypes,
      pathStripPrefixes: stripPrefixes,
    },
  };

  const outAbs = path.isAbsolute(summaryPath)
    ? summaryPath
    : path.join(process.env.GITHUB_WORKSPACE || process.cwd(), summaryPath);
  fs.mkdirSync(path.dirname(outAbs), { recursive: true });
  fs.writeFileSync(outAbs, JSON.stringify(summary, null, 2), 'utf8');

  const maxAnnotations = 50;
  for (let i = 0; i < Math.min(findings.length, maxAnnotations); i++) {
    const f = findings[i];
    const sev =
      String(f.severity).toUpperCase() === 'WARNING' ? 'warning' : 'error';
    const filePart =
      f.file && f.file !== '(no-file)'
        ? `file=${f.file}${f.line ? `,line=${f.line}` : ''}`
        : '';
    const msg = f.message.replace(/\r?\n/g, ' ').slice(0, 200);
    if (filePart) {
      console.log(`::${sev} ${filePart}::${msg}`);
    } else {
      console.log(`::${sev}::${msg}`);
    }
  }
  if (findings.length > maxAnnotations) {
    console.log(
      `::warning::${findings.length - maxAnnotations} additional findings omitted from annotations`,
    );
  }

  console.log(`SUMMARY_PATH=${outAbs}`);
  console.log(`OK_COUNT=${summary.counts.ok}`);
  console.log(`NOK_COUNT=${summary.counts.nok}`);
  console.log(`FINDING_COUNT=${summary.counts.findings}`);
  console.log(`CHECKED_COUNT=${summary.counts.checked}`);
}

main();