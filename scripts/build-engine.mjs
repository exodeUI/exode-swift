#!/usr/bin/env node
/**
 * Builds the resources that the Swift package ships inside its WKWebView.
 *
 *   node packages/swift/scripts/build-engine.mjs           # write resources
 *   node packages/swift/scripts/build-engine.mjs --check   # fail if stale (CI)
 *
 * The JavaScript bridge is the *same* source the Flutter package uses
 * (`packages/flutter/bridge`). It posts messages to
 * `window.webkit.messageHandlers.exodeui` when no Flutter-style channel is
 * present, so one bridge implementation serves both runtimes. The document and
 * engine bundle are copied from `packages/flutter` so the two SDKs can never
 * drift apart.
 */
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const requireFromReact = createRequire(
  new URL('../../react/package.json', import.meta.url),
);
const { build } = requireFromReact('esbuild');

const here = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(here, '..');
const repoRoot = join(packageRoot, '../..');
const entry = join(repoRoot, 'packages/flutter/bridge/index.ts');
const resources = join(packageRoot, 'Sources/ExodeUI/Resources');
const bundlePath = join(resources, 'engine.bundle.js');
const htmlPath = join(resources, 'index.html');
const sourceHtmlPath = join(repoRoot, 'packages/flutter/assets/index.html');

const reactPkg = JSON.parse(readFileSync(join(repoRoot, 'packages/react/package.json'), 'utf8'));
const checkOnly = process.argv.includes('--check');

const result = await build({
  entryPoints: [entry],
  absWorkingDir: repoRoot,
  bundle: true,
  write: false,
  format: 'iife',
  globalName: 'ExodeUIBundle',
  platform: 'browser',
  target: ['es2020'],
  minify: true,
  legalComments: 'none',
  charset: 'utf8',
  sourcemap: false,
  define: {
    'process.env.NODE_ENV': '"production"',
    __EXODE_ENGINE_VERSION__: JSON.stringify(reactPkg.version ?? 'dev'),
  },
  nodePaths: [join(repoRoot, 'node_modules'), join(repoRoot, 'packages/react/node_modules')],
  logLevel: 'warning',
});

const output = result.outputFiles?.[0];
if (!output) {
  console.error('esbuild produced no output.');
  process.exit(1);
}

const nextBundle = output.text;
const nextHtml = readFileSync(sourceHtmlPath, 'utf8');

if (checkOnly) {
  const problems = [];
  if (!existsSync(bundlePath)) {
    problems.push(`Missing ${bundlePath}. Run: npm run build:swift`);
  } else if (readFileSync(bundlePath, 'utf8').trimEnd() !== nextBundle.trimEnd()) {
    problems.push('Sources/ExodeUI/Resources/engine.bundle.js is stale.');
  }
  if (!existsSync(htmlPath)) {
    problems.push(`Missing ${htmlPath}. Run: npm run build:swift`);
  } else if (readFileSync(htmlPath, 'utf8') !== nextHtml) {
    problems.push('Sources/ExodeUI/Resources/index.html differs from packages/flutter/assets/index.html.');
  }
  if (problems.length > 0) {
    console.error(
      problems.join('\n') +
        '\nThe React runtime or the Flutter bridge changed but the Swift resources were not rebuilt.' +
        '\nRun: npm run build:swift',
    );
    process.exit(1);
  }
  console.log(`Swift resources are up to date (engine ${reactPkg.version}).`);
} else {
  mkdirSync(resources, { recursive: true });
  writeFileSync(bundlePath, nextBundle);
  writeFileSync(htmlPath, nextHtml);
  const kb = (Buffer.byteLength(nextBundle) / 1024).toFixed(0);
  console.log(`Wrote ${bundlePath} (${kb} KB, engine ${reactPkg.version}).`);
  console.log(`Wrote ${htmlPath}.`);
}
