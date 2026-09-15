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
  let file = md.script || md.library || null;
  let line = typeof md.line === 'number' ? md.line : null;

  // Fallback: parse ", path, Line: N" still present in errorText
  const text = String(entry.errorText || '');
  if ((!file || line == null) && text) {
    const m = text.match(
      /((?:\/|\w:)?[^\s,]+\.(?:ctl|pnl|xml))\s*,\s*Line:\s*(\d+)/i,
    );
    if (m) {
      file = file || m[1];
      if (line == null) line = Number.parseInt(m[2], 10);
    }
  }

  // Fallback: stacktrace first frame
  if ((!file || line == null) && Array.isArray(md.stacktrace) && md.stacktrace[0]) {
    const fr = md.stacktrace[0];
    file = file || fr.filePath || null;
    if (line == null && typeof fr.line === 'number') line = fr.line;
  }

  return { file, line };
}

function cleanMessageText(errorText) {
  let msg = String(errorText || '').split('\n')[0].trim();
  // OA often ends with "Location:" when Script/Line follow on next lines
  msg = msg.replace(/\s*Location:\s*$/i, '').trim();
  // Drop trailing ", /path, Line: N" if still embedded (already in metadata)
  msg = msg.replace(
    /,\s*(?:\/|\w:)?[^\s,]+\.(?:ctl|pnl|xml)\s*,\s*Line:\s*\d+\s*$/i,
    '',
  );
  return msg.trim();
}

function buildMessage(entry, file, line) {
  const base = cleanMessageText(entry.errorText);
  const parts = [base];
  if (file && file !== '(no-file)') {
    parts.push(`@ ${file}${line != null ? `:${line}` : ''}`);
  }
  const snip = String(entry.metadata?.raw || '')
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean)[0];
  if (snip && !base.includes(snip)) {
    parts.push(`| ${snip}`);
  }
  return parts.join(' ');
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

function serializeEntry(entry, stripPrefixes) {
  const md = entry.metadata || {};
  return {
    managerName: entry.managerName,
    managerNum: entry.managerNum,
    identifier: entry.identifier,
    timeStampString: entry.timeStampString,
    errorType: entry.errorType,
    errorPriority: entry.errorPriority,
    errorCode: entry.errorCode ?? null,
    errorCatalog: entry.errorCatalog ?? null,
    errorText: entry.errorText,
    metadata: {
      script: md.script ?? null,
      library: md.library ?? null,
      line: typeof md.line === 'number' ? md.line : null,
      raw: md.raw ?? null,
      stacktrace: md.stacktrace ?? null,
      scriptNormalized: normalizePath(md.script, stripPrefixes),
      libraryNormalized: normalizePath(md.library, stripPrefixes),
    },
    rawLines: entry.rawLines || [],
  };
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
  const filteredEntries = [];
  /** @type {Map<string, string>} matchKey -> display path */
  const nokDisplay = new Map();

  for (const entry of allEntries) {
    if (!isFinding(entry, severities, includeTypes)) continue;

    filteredEntries.push(serializeEntry(entry, stripPrefixes));

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

    const line = loc.line != null ? loc.line : null;
    const message = buildMessage(entry, display, line);
    const snippet = String(entry.metadata?.raw || '')
      .split('\n')
      .map((s) => s.trim())
      .filter(Boolean)
      .slice(0, 3)
      .join(' | ');

    findings.push({
      file: display,
      matchKey: key,
      line,
      severity: entry.errorPriority,
      errorType: entry.errorType,
      errorCode: entry.errorCode ?? null,
      errorCatalog: entry.errorCatalog ?? null,
      message,
      messageRaw: String(entry.errorText || ''),
      snippet: snippet || null,
      metadata: {
        script: entry.metadata?.script ?? null,
        library: entry.metadata?.library ?? null,
        line: typeof entry.metadata?.line === 'number' ? entry.metadata.line : null,
        raw: entry.metadata?.raw ?? null,
      },
      rawLines: entry.rawLines || [],
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

  const summaryFindings = findings.map(({ matchKey, ...rest }) => rest);

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
    findings: summaryFindings,
    filteredEntries,
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

  // Always print filtered log JSON for CI debugging (line/message verification)
  console.log('--- filtered-log-json-begin ---');
  console.log(
    JSON.stringify(
      {
        filters: summary.filters,
        counts: summary.counts,
        findings: summaryFindings,
        filteredEntries,
      },
      null,
      2,
    ),
  );
  console.log('--- filtered-log-json-end ---');

  const maxAnnotations = 50;
  for (let i = 0; i < Math.min(findings.length, maxAnnotations); i++) {
    const f = findings[i];
    const sev =
      String(f.severity).toUpperCase() === 'WARNING' ? 'warning' : 'error';
    const filePart =
      f.file && f.file !== '(no-file)'
        ? `file=${f.file}${f.line != null ? `,line=${f.line}` : ''}`
        : '';
    // Keep annotation text single-line; include location explicitly in message
    const msg = f.message.replace(/\r?\n/g, ' ').slice(0, 300);
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