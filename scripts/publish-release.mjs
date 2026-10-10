#!/usr/bin/env node
// Uploads a built APK or Windows installer to the Supabase "releases" bucket
// and records it in app_versions, which the landing page and the in-app
// update check read.
//
// Needs the secret (service-role) key, so run it only on your own machine:
//   SUPABASE_URL=https://xyz.supabase.co
//   SUPABASE_SECRET_KEY=sb_secret_...   (or a legacy service_role JWT)
// Put them in a git-ignored .env at the repo root, or export them.
//
// Usage (from the repo root):
//   node scripts/publish-release.mjs android [--notes "What changed"] [--file path] [--dry-run]
//   node scripts/publish-release.mjs windows [--notes-file notes.txt]
//
// The version and build number come from app/pubspec.yaml (version: 1.2.0+5).
// Bump the build number for every release: the app only offers an update
// when the published build number is higher than the installed one.

import { existsSync, readFileSync, statSync } from 'node:fs';
import { basename, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// Supabase Storage rejects larger files on the free plan unless the global
// upload limit is raised in the dashboard.
const SIZE_WARNING_BYTES = 50 * 1024 * 1024;

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function loadEnvFile() {
  const file = resolve(root, '.env');
  if (existsSync(file)) process.loadEnvFile(file);
}

function readPubspecVersion() {
  const pubspec = readFileSync(resolve(root, 'app/pubspec.yaml'), 'utf8');
  const match = pubspec.match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m);
  if (!match) fail('Could not find "version: x.y.z+build" in app/pubspec.yaml');
  return { version: match[1], build: Number(match[2]) };
}

function defaultArtifact(platform, version) {
  return platform === 'android'
    ? resolve(root, 'app/build/app/outputs/flutter-apk/app-release.apk')
    : resolve(root, `installer/Output/FinTrack-Setup-${version}.exe`);
}

function authHeaders(key) {
  // New sb_secret_ keys go in the apikey header only; legacy keys are JWTs
  // and are also sent as the bearer token.
  const headers = { apikey: key };
  if (key.startsWith('eyJ')) headers.Authorization = `Bearer ${key}`;
  return headers;
}

async function request(url, init, what) {
  const response = await fetch(url, init);
  if (!response.ok) {
    const body = await response.text();
    fail(`${what} failed (${response.status}): ${body}`);
  }
  return response;
}

async function main() {
  const { positionals, values } = parseArgs({
    allowPositionals: true,
    options: {
      file: { type: 'string' },
      notes: { type: 'string' },
      'notes-file': { type: 'string' },
      'dry-run': { type: 'boolean', default: false },
    },
  });

  const platform = positionals[0];
  if (platform !== 'android' && platform !== 'windows') {
    fail('Usage: node scripts/publish-release.mjs <android|windows> [--file path] [--notes text] [--dry-run]');
  }

  loadEnvFile();
  const baseUrl = process.env.SUPABASE_URL?.replace(/\/+$/, '');
  const key = process.env.SUPABASE_SECRET_KEY ?? process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!baseUrl || !key) fail('Set SUPABASE_URL and SUPABASE_SECRET_KEY (in .env or the environment).');
  if (key.startsWith('sb_publishable_')) fail('That is the publishable key; the secret key is needed to publish.');

  const { version, build } = readPubspecVersion();
  const file = resolve(values.file ?? defaultArtifact(platform, version));
  if (!existsSync(file)) fail(`Build not found: ${file}\nBuild it first (see README) or pass --file.`);

  const notes = values['notes-file']
    ? readFileSync(resolve(values['notes-file']), 'utf8').trim()
    : (values.notes ?? null);

  const size = statSync(file).size;
  const extension = platform === 'android' ? 'apk' : 'exe';
  const objectPath = `${platform}/FinTrack-${version}-b${build}.${extension}`;
  const downloadUrl = `${baseUrl}/storage/v1/object/public/releases/${objectPath}`;

  console.log(`Platform:  ${platform}`);
  console.log(`Version:   ${version} (build ${build})`);
  console.log(`File:      ${basename(file)} (${(size / 1024 / 1024).toFixed(1)} MB)`);
  console.log(`Upload to: releases/${objectPath}`);
  if (size > SIZE_WARNING_BYTES) {
    console.warn('Warning: over 50 MB. Raise the Storage upload limit, or build with --split-per-abi.');
  }

  const headers = authHeaders(key);

  // Refuse to publish the same build twice: installed apps compare build numbers.
  const existing = await request(
    `${baseUrl}/rest/v1/app_versions?platform=eq.${platform}&build_number=gte.${build}&select=version,build_number`,
    { headers },
    'Checking existing releases',
  ).then((r) => r.json());
  if (existing.length > 0) {
    const latest = existing.map((r) => `${r.version}+${r.build_number}`).join(', ');
    fail(`A ${platform} release with build ${build} or higher already exists (${latest}). Bump the build number in app/pubspec.yaml.`);
  }

  if (values['dry-run']) {
    console.log('Dry run: nothing uploaded.');
    return;
  }

  await request(
    `${baseUrl}/storage/v1/object/releases/${objectPath}`,
    {
      method: 'POST',
      headers: {
        ...headers,
        'Content-Type': platform === 'android' ? 'application/vnd.android.package-archive' : 'application/octet-stream',
        'x-upsert': 'false',
        'cache-control': '3600',
      },
      body: readFileSync(file),
    },
    'Upload',
  );
  console.log('Uploaded.');

  const [row] = await request(
    `${baseUrl}/rest/v1/app_versions`,
    {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json', Prefer: 'return=representation' },
      body: JSON.stringify({
        platform,
        version,
        build_number: build,
        download_url: downloadUrl,
        file_size: size,
        release_notes: notes,
      }),
    },
    'Recording the release',
  ).then((r) => r.json());

  console.log(`Published ${platform} ${row.version} (build ${row.build_number}).`);
  console.log(downloadUrl);
}

main().catch((error) => fail(error.message));
