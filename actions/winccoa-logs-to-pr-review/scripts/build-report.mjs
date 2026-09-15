#!/usr/bin/env node
/**
 * Build OK/NOK summary from classic WinCC OA logs via npm-winccoa-log-reader.
 *
 * Env:
 *   LOG_PATH, SUMMARY_PATH, SEVERITIES, INCLUDE_ERROR_TYPES,
 *   PATH_STRIP_PREFIXES, REPORT_TITLE, COMMENT_MARKER, GITHUB_WORKSPACE,
 *   IGNORE_OUTSIDE_PR_CHANGES, GITHUB_TOKEN, GITHUB_*, ANNOTATE_IGNORED
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

  if ((!file || line == null) && Array.isArray(md.stacktrace) && md.stacktrace[0]) {
    const fr = md.stacktrace[0];
    file = file || fr.filePath || null;
    if (line == null && typeof fr.line === 'number') line = fr.line;
  }

  return { file, line };
}

function cleanMessageText(errorText) {
  let msg = String(errorText || '').split('\n')[0].trim();
  msg = msg.replace(/\s*Location:\s*$/i, '').trim();
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

function eventPayload() {
  const p = process.env.GITHUB_EVENT_PATH;
  if (!p || !fs.existsSync(p)) return null;
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
}

async function ghGet(urlPath) {
  const token = process.env.GITHUB_TOKEN;
  if (!token) {
    throw new Error('GITHUB_TOKEN is required to list PR changed files');
  }
  const base = (process.env.GITHUB_API_URL || 'https://api.github.com').replace(
    /\/$/,
    '',
  );
  const res = await fetch(`${base}${urlPath}`, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'winccoa-logs-to-pr-review',
    },
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { raw: text };
  }
  if (!res.ok) {
    throw new Error(
      `GitHub API GET ${urlPath} -> ${res.status}: ${data?.message || text}`,
    );
  }
  return data;
}

/**
 * Load repo-relative paths changed in the current pull_request (file-level).
 * Returns null when ignore mode is off or not a PR / unavailable.
 */
async function loadPrChangedFiles(enabled) {
  if (!enabled) {
    return { enabled: false, files: [], source: 'disabled' };
  }
  if (process.env.GITHUB_EVENT_NAME !== 'pull_request') {
    console.log(
      'ignore-outside-pr-changes is true but event is not pull_request; no ignore applied',
    );
    return { enabled: false, files: [], source: 'not-pull_request' };
  }

  const payload = eventPayload();
  const prNumber = payload?.pull_request?.number;
  const [owner, repo] = String(process.env.GITHUB_REPOSITORY || '').split('/');
  if (!prNumber || !owner || !repo) {
    console.log(
      '::warning::ignore-outside-pr-changes requested but PR context is incomplete; no ignore applied',
    );
    return { enabled: false, files: [], source: 'missing-pr-context' };
  }

  const files = [];
  let page = 1;
  const perPage = 100;
  while (page <= 30) {
    const batch = await ghGet(
      `/repos/${owner}/${repo}/pulls/${prNumber}/files?per_page=${perPage}&page=${page}`,
    );
    if (!Array.isArray(batch) || batch.length === 0) break;
    for (const f of batch) {
      if (f?.filename) files.push(String(f.filename).replace(/\\/g, '/'));
      if (f?.previous_filename) {
        files.push(String(f.previous_filename).replace(/\\/g, '/'));
      }
    }
    if (batch.length < perPage) break;
    page += 1;
  }

  const unique = [...new Set(files)].sort();
  console.log(
    `PR #${prNumber} changed files for ignore filter: ${unique.length}`,
  );
  return { enabled: true, files: unique, source: 'pull_request_files', prNumber };
}

function findingTouchesPrChanges(finding, changedFiles) {
  if (!finding?.file || finding.file === '(no-file)') {
    // System-level findings have no file: treat as in-scope (do not ignore)
    return true;
  }
  return changedFiles.some((cf) => pathsReferToSameFile(finding.file, cf));
}

function rebuildNokFromFindings(findings) {
  const nokDisplay = new Map();
  for (const f of findings) {
    const key = f.matchKey || f.file;
    const prev = nokDisplay.get(key);
    nokDisplay.set(key, preferDisplayPath(prev, f.file));
  }
  const nokList = [...nokDisplay.entries()]
    .filter(([k]) => k !== '(no-file)')
    .map(([, display]) => display)
    .sort();
  const systemNok = nokDisplay.has('(no-file)');
  return {
    nokFiles: systemNok ? [...nokList, '(no-file)'] : nokList,
    nokCount: nokList.length + (systemNok ? 1 : 0),
  };
}

async function main() {
  const logPath = process.env.LOG_PATH;
  const summaryPath =
    process.env.SUMMARY_PATH || '.artifacts/winccoa-log-report.json';
  const pkgRoot = process.env.LOG_READER_PKG_ROOT;
  const title = process.env.REPORT_TITLE || 'WinCC OA log report';
  const marker =
    process.env.COMMENT_MARKER || '<!-- winccoa-logs-to-pr-review -->';
  const ignoreOutside =
    String(process.env.IGNORE_OUTSIDE_PR_CHANGES || 'false') === 'true';
  // When ignoring outside changes, do not annotate ignored findings by default
  const annotateIgnored =
    String(process.env.ANNOTATE_IGNORED || 'false') === 'true';

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
      inPrChanges: true,
      ignored: false,
      metadata: {
        script: entry.metadata?.script ?? null,
        library: entry.metadata?.library ?? null,
        line:
          typeof entry.metadata?.line === 'number' ? entry.metadata.line : null,
        raw: entry.metadata?.raw ?? null,
      },
      rawLines: entry.rawLines || [],
    });
  }

  const prChanges = await loadPrChangedFiles(ignoreOutside);
  let activeFindings = findings;
  let ignoredFindings = [];

  if (prChanges.enabled) {
    for (const f of findings) {
      const inPr = findingTouchesPrChanges(f, prChanges.files);
      f.inPrChanges = inPr;
      f.ignored = !inPr;
    }
    activeFindings = findings.filter((f) => !f.ignored);
    ignoredFindings = findings.filter((f) => f.ignored);
    console.log(
      `ignore-outside-pr-changes: total=${findings.length} active=${activeFindings.length} ignored=${ignoredFindings.length}`,
    );
  }

  // OK/NOK based on active findings only (when ignore is on, outside files do not make NOK)
  const { nokFiles, nokCount } = rebuildNokFromFindings(activeFindings);
  const nokKeys = activeFindings.map((f) => f.matchKey || f.file);
  const okFiles = [...checkedFromParam]
    .filter((f) => !nokKeys.some((k) => pathsReferToSameFile(f, k)))
    .sort();
  const checkedCount = okFiles.length + nokCount;

  const summaryFindings = activeFindings.map(({ matchKey, ...rest }) => rest);
  const summaryIgnored = ignoredFindings.map(({ matchKey, ...rest }) => rest);

  const summary = {
    title,
    marker,
    logPath,
    generatedAt: new Date().toISOString(),
    counts: {
      checked: checkedCount,
      ok: okFiles.length,
      nok: nokCount,
      findings: activeFindings.length,
      findingsTotal: findings.length,
      findingsIgnored: ignoredFindings.length,
      paramInfoFiles: checkedFromParam.size,
    },
    okFiles,
    nokFiles,
    findings: summaryFindings,
    findingsIgnored: summaryIgnored,
    filteredEntries,
    prChanges: {
      ignoreOutsidePrChanges: ignoreOutside,
      applied: prChanges.enabled,
      source: prChanges.source,
      prNumber: prChanges.prNumber ?? null,
      changedFileCount: prChanges.files.length,
      changedFiles: prChanges.files,
    },
    filters: {
      severities,
      includeErrorTypes: includeTypes,
      pathStripPrefixes: stripPrefixes,
      ignoreOutsidePrChanges: ignoreOutside,
    },
  };

  const outAbs = path.isAbsolute(summaryPath)
    ? summaryPath
    : path.join(process.env.GITHUB_WORKSPACE || process.cwd(), summaryPath);
  fs.mkdirSync(path.dirname(outAbs), { recursive: true });
  fs.writeFileSync(outAbs, JSON.stringify(summary, null, 2), 'utf8');

  console.log('--- filtered-log-json-begin ---');
  console.log(
    JSON.stringify(
      {
        filters: summary.filters,
        prChanges: summary.prChanges,
        counts: summary.counts,
        findings: summaryFindings,
        findingsIgnored: summaryIgnored,
        filteredEntries,
      },
      null,
      2,
    ),
  );
  console.log('--- filtered-log-json-end ---');

  const toAnnotate = annotateIgnored
    ? findings
    : activeFindings;
  const maxAnnotations = 50;
  for (let i = 0; i < Math.min(toAnnotate.length, maxAnnotations); i++) {
    const f = toAnnotate[i];
    const sev =
      String(f.severity).toUpperCase() === 'WARNING' ? 'warning' : 'error';
    const filePart =
      f.file && f.file !== '(no-file)'
        ? `file=${f.file}${f.line != null ? `,line=${f.line}` : ''}`
        : '';
    const prefix = f.ignored ? '[ignored outside PR] ' : '';
    const msg = `${prefix}${f.message}`.replace(/\r?\n/g, ' ').slice(0, 300);
    if (filePart) {
      console.log(`::${sev} ${filePart}::${msg}`);
    } else {
      console.log(`::${sev}::${msg}`);
    }
  }
  if (toAnnotate.length > maxAnnotations) {
    console.log(
      `::warning::${toAnnotate.length - maxAnnotations} additional findings omitted from annotations`,
    );
  }
  if (ignoredFindings.length > 0 && !annotateIgnored) {
    console.log(
      `::notice::Ignored ${ignoredFindings.length} finding(s) outside PR changed files (ignore-outside-pr-changes=true)`,
    );
  }

  console.log(`SUMMARY_PATH=${outAbs}`);
  console.log(`OK_COUNT=${summary.counts.ok}`);
  console.log(`NOK_COUNT=${summary.counts.nok}`);
  console.log(`FINDING_COUNT=${summary.counts.findings}`);
  console.log(`FINDING_COUNT_TOTAL=${summary.counts.findingsTotal}`);
  console.log(`IGNORED_COUNT=${summary.counts.findingsIgnored}`);
  console.log(`CHECKED_COUNT=${summary.counts.checked}`);
}

main().catch((err) => {
  console.error(`::error::${err.message}`);
  process.exit(1);
});