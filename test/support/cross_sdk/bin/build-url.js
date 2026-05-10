#!/usr/bin/env node
//
// Cross-SDK URL builder. Reads one JSON object per line from stdin
// describing a (provider, intent, source) triple, calls the
// vendor's official URL-builder SDK, and writes one JSON line per
// output to stdout: `{ "url": "<built URL>" }` or
// `{ "error": "<message>" }`.
//
// Used by `test/image/components/cross_sdk_test.exs` to compare
// `Image.Components.URL.<provider>/2` output against the canonical
// vendor builders.
//
// Input shape:
//   {
//     "provider": "cloudinary" | "imgix" | "imagekit",
//     "source":   "/cat.jpg",
//     "host":     "<optional, provider-specific>",
//     "intent":   { ... per-vendor option keys ... }
//   }
//
// Output shape:
//   { "url": "<the URL the SDK built>" }   on success
//   { "error": "<message>" }               on failure
//
// One JSON object per input line, one per output line — strict
// line-buffered so the Elixir side can interleave many requests
// without restarting Node.

import { v2 as cloudinary } from "cloudinary";
import ImgixClient from "@imgix/js-core";
import ImageKit from "imagekit-javascript";
import readline from "node:readline";

const rl = readline.createInterface({ input: process.stdin, terminal: false });

rl.on("line", (line) => {
  let req;
  try {
    req = JSON.parse(line);
  } catch (err) {
    process.stdout.write(JSON.stringify({ error: `bad JSON: ${err.message}` }) + "\n");
    return;
  }

  try {
    const url = build(req);
    process.stdout.write(JSON.stringify({ url }) + "\n");
  } catch (err) {
    process.stdout.write(JSON.stringify({ error: err.message }) + "\n");
  }
});

function build({ provider, source, host, intent }) {
  switch (provider) {
    case "cloudinary":  return buildCloudinary({ source, host, intent });
    case "imgix":       return buildImgix({ source, host, intent });
    case "imagekit":    return buildImageKit({ source, host, intent });
    default: throw new Error(`unknown provider: ${provider}`);
  }
}

// ── Cloudinary ─────────────────────────────────────────────────
//
// Cloudinary's SDK takes `cloud_name` config + a `transformation`
// array. Each element is an object whose keys map to the
// `c_/g_/w_/h_/q_/f_/e_…` URL tokens.

function buildCloudinary({ source, host, intent }) {
  cloudinary.config({
    cloud_name: intent.cloud_name || "demo",
    secure: true,
    secure_distribution: stripProtocol(host),
    // Disable the `?_a=…` analytics fingerprint so URLs are
    // directly comparable to image_components output.
    analytics: false,
  });

  // Strip leading slash — Cloudinary expects a public_id, not a path.
  const publicId = source.replace(/^\//, "");
  return cloudinary.url(publicId, intent.options || {});
}

// ── imgix ──────────────────────────────────────────────────────
//
// imgix's SDK takes a domain + a per-request options map of
// `w/h/fit/crop/auto/q/fm/blur/…` keys.

function buildImgix({ source, host, intent }) {
  const domain = (host || "assets.imgix.net").replace(/^https?:\/\//, "");
  // `includeLibraryParam: false` disables the `ixlib=js-3.8.0`
  // SDK-tracking parameter so URLs are directly comparable.
  const client = new ImgixClient({ domain, includeLibraryParam: false });
  return client.buildURL(source, intent.options || {});
}

// ── ImageKit ───────────────────────────────────────────────────
//
// ImageKit's SDK takes a urlEndpoint + a transformation array of
// objects whose keys are the documented `w/h/c/fo/q/f/e-…`
// tokens.

function buildImageKit({ source, host, intent }) {
  const urlEndpoint = host || "https://ik.imagekit.io/demo";
  // Default transformationPosition is "path" but make it explicit;
  // image_components emits the path-prefix form (`/tr:…/source`)
  // not the query-string form (`?tr=…`).
  const ik = new ImageKit({ urlEndpoint, transformationPosition: "path" });
  return ik.url({
    path: source,
    transformation: intent.transformation || [],
  });
}

function stripProtocol(host) {
  return host ? host.replace(/^https?:\/\//, "") : undefined;
}
