#!/usr/bin/env node
/**
 * Upsert PR comment and optionally create a PR review with line comments.
 * Uses GitHub REST API with GITHUB_TOKEN.
 *
 * Env: SUMMARY_PATH, COMMENT_ON_PR, REVIEW_COMMENTS, GITHUB_*, COMMENT_MARKER
 */
import fs from 'node:fs';
import path from 'node:path';

function mustReadJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function eventPayload() {
  const p = process.env.GITHUB_EVENT_PATH;
  if (!p || !fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

async function gh(method, urlPath, body) {
  const token = process.env.GITHUB_TOKEN;
  if (!token) throw new Error('GITHUB_TOKEN is required for PR reporting');
  const base = (process.env.GITHUB_API_URL || 'https://api.github.com').replace(
    /\/$/,
    '',
  );
  const res = await fetch(`${base}${urlPath}`, {
    method,
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'winccoa-logs-to-pr-review',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { raw: text };
  }
  if (!res.ok) {
    const msg = data?.message || text || res.statusText;
    const err = new Error(`GitHub API ${method} ${urlPath} -> ${res.status}: ${msg}`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function buildCommentBody(summary) {
  const marker = summary.marker || '<!-- winccoa-logs-to-pr-review -->';
  const title = summary.title || 'WinCC OA log report';
  const c = summary.counts || {};
  const runUrl =
    process.env.GITHUB_SERVER_URL &&
    process.env.GITHUB_REPOSITORY &&
    process.env.GITHUB_RUN_ID
      ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
      : '';

  const top = (summary.findings || []).slice(0, 20).map((f) => {
    const loc =
      f.file && f.file !== '(no-file)'
        ? f.line
          ? `\`${f.file}:${f.line}\``
          : `\`${f.file}\``
        : '_no file_';
    return `| ${f.severity || '?'} | ${loc} | ${escapeCell(f.message || '')} |`;
  });

  const lines = [
    marker,
    `## ${title}`,
    '',
    `| Metric | Count |`,
    `| --- | ---: |`,
    `| Checked files | ${c.checked ?? 0} |`,
    `| OK | ${c.ok ?? 0} |`,
    `| NOK | ${c.nok ?? 0} |`,
    `| Findings | ${c.findings ?? 0} |`,
    '',
  ];

  if ((summary.nokFiles || []).length > 0) {
    lines.push('### NOK files', '');
    for (const f of summary.nokFiles.slice(0, 40)) {
      lines.push(`- \`${f}\``);
    }
    if (summary.nokFiles.length > 40) {
      lines.push(`- … and ${summary.nokFiles.length - 40} more`);
    }
    lines.push('');
  }

  if (top.length > 0) {
    lines.push('### Findings (top 20)', '');
    lines.push('| Severity | Location | Message |');
    lines.push('| --- | --- | --- |');
    lines.push(...top);
    lines.push('');
  } else {
    lines.push('_No matching findings._', '');
  }

  if (runUrl) {
    lines.push(`- Run: ${runUrl}`);
  }
  if (summary.logPath) {
    lines.push(`- Log: \`${path.basename(summary.logPath)}\``);
  }
  lines.push('');
  return lines.join('\n');
}

function escapeCell(s) {
  return String(s).replace(/\|/g, '\\|').replace(/\r?\n/g, ' ').slice(0, 180);
}

async function upsertIssueComment(owner, repo, issueNumber, body, marker) {
  const comments = await gh(
    'GET',
    `/repos/${owner}/${repo}/issues/${issueNumber}/comments?per_page=100`,
  );
  const existing = (comments || []).find(
    (c) =>
      (c.user?.type === 'Bot' || c.user?.login?.endsWith('[bot]')) &&
      String(c.body || '').includes(marker),
  );
  if (existing) {
    await gh('PATCH', `/repos/${owner}/${repo}/issues/comments/${existing.id}`, {
      body,
    });
    console.log(`Updated existing PR comment ${existing.id}`);
  } else {
    const created = await gh(
      'POST',
      `/repos/${owner}/${repo}/issues/${issueNumber}/comments`,
      { body },
    );
    console.log(`Created PR comment ${created.id}`);
  }
}

async function createReview(owner, repo, pullNumber, commitId, findings) {
  // Prefer a single review with multiple comments; fall back silently on 422.
  const comments = [];
  const seen = new Set();
  for (const f of findings) {
    if (!f.file || f.file === '(no-file)' || !f.line) continue;
    const key = `${f.file}:${f.line}:${f.message}`;
    if (seen.has(key)) continue;
    seen.add(key);
    comments.push({
      path: f.file,
      line: f.line,
      side: 'RIGHT',
      body: `**${f.severity || 'WARNING'}** (WinCC OA)\n\n${f.message}`,
    });
    if (comments.length >= 30) break;
  }
  if (comments.length === 0) {
    console.log('No line-anchored findings for review comments');
    return;
  }

  try {
    const review = await gh(
      'POST',
      `/repos/${owner}/${repo}/pulls/${pullNumber}/reviews`,
      {
        commit_id: commitId,
        event: 'COMMENT',
        body: 'Automated WinCC OA log findings (line comments).',
        comments,
      },
    );
    console.log(`Created PR review ${review.id} with ${comments.length} comment(s)`);
  } catch (err) {
    // Diff-line mismatches often 422 — try one-by-one to post what we can.
    console.log(
      `::warning::Batch review failed (${err.message}); trying individual comments`,
    );
    let ok = 0;
    for (const c of comments) {
      try {
        await gh('POST', `/repos/${owner}/${repo}/pulls/${pullNumber}/comments`, {
          commit_id: commitId,
          path: c.path,
          line: c.line,
          side: 'RIGHT',
          body: c.body,
        });
        ok += 1;
      } catch (e2) {
        console.log(
          `::warning::Skipped review comment ${c.path}:${c.line} (${e2.message})`,
        );
      }
    }
    console.log(`Posted ${ok}/${comments.length} individual review comment(s)`);
  }
}

async function main() {
  const summaryPath = process.env.SUMMARY_PATH;
  if (!summaryPath || !fs.existsSync(summaryPath)) {
    console.error(`::error::Summary not found: ${summaryPath}`);
    process.exit(2);
  }

  const commentOnPr = String(process.env.COMMENT_ON_PR || 'true') === 'true';
  const reviewComments =
    String(process.env.REVIEW_COMMENTS || 'false') === 'true';

  if (!commentOnPr && !reviewComments) {
    console.log('PR reporting disabled (comment-on-pr and review-comments false)');
    return;
  }

  if (process.env.GITHUB_EVENT_NAME !== 'pull_request') {
    console.log(
      `Skipping PR API steps (event=${process.env.GITHUB_EVENT_NAME || 'unknown'})`,
    );
    return;
  }

  const summary = mustReadJson(summaryPath);
  const payload = eventPayload();
  const pr = payload?.pull_request;
  if (!pr?.number) {
    console.log('No pull_request payload; skipping PR API steps');
    return;
  }

  const [owner, repo] = String(process.env.GITHUB_REPOSITORY || '').split('/');
  if (!owner || !repo) {
    console.error('::error::GITHUB_REPOSITORY is not set');
    process.exit(2);
  }

  const body = buildCommentBody(summary);
  const marker = summary.marker || '<!-- winccoa-logs-to-pr-review -->';

  if (commentOnPr) {
    await upsertIssueComment(owner, repo, pr.number, body, marker);
  }

  if (reviewComments) {
    const commitId = pr.head?.sha || process.env.GITHUB_SHA;
    if (!commitId) {
      console.log('::warning::No commit SHA for review comments');
    } else {
      await createReview(owner, repo, pr.number, commitId, summary.findings || []);
    }
  }
}

main().catch((err) => {
  console.error(`::error::${err.message}`);
  process.exit(1);
});
