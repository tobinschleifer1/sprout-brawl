import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const { handleRequest } = createRequire(import.meta.url)('../serve.cjs');
const request = (url) => new Promise((resolve, reject) => {
  let status;
  try { handleRequest({ url }, { writeHead(code) { status = code; }, end(body) { resolve({ status, body }); } }); }
  catch (err) { reject(err); }
});
assert.equal((await request('/%ZZ')).status, 400, 'malformed URL must not crash the preview server');
assert.equal((await request('/%00')).status, 400, 'null byte must not reach the file API');
assert.equal((await request('/../web-secret/private.txt')).status, 403, 'a sibling sharing the web prefix is outside the root');
assert.equal((await request('/index.html')).status, 200, 'valid requests still work after bad requests');
console.log('PASS preview server: malformed URLs, null bytes, sibling traversal and valid requests');
