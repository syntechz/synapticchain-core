const express = require('express');
const redis = require('redis');
const rateLimit = require('express-rate-limit');

const app = express();
app.use(express.json());

// ── CONFIG ──
const ALPHA_HOST = process.env.ALPHA_HOST || '79.143.177.212';
const BRAVO_HOST = process.env.BRAVO_HOST || '147.93.1.73';
const ALPHA_PORTS = Array.from({length: 9}, (_, i) => 8545 + i);
const BRAVO_PORTS = Array.from({length: 9}, (_, i) => 8545 + i);
const CACHE_TTL = parseInt(process.env.CACHE_TTL) || 3;

// ── REDIS ──
let redisClient = null;
(async () => {
  try {
    redisClient = redis.createClient({ socket: { host: 'localhost', port: 6379 } });
    redisClient.on('error', (err) => console.log('Redis error:', err.message));
    await redisClient.connect();
    console.log('Redis connected');
  } catch (e) {
    console.log('Redis not available — running without cache');
  }
})();

// ── NODE HEALTH ──
const nodeHealth = new Map();
function nodeKey(host, port) { return `${host}:${port}`; }

[...ALPHA_PORTS.map(p => [ALPHA_HOST, p]), ...BRAVO_PORTS.map(p => [BRAVO_HOST, p])]
  .forEach(([h, p]) => nodeHealth.set(nodeKey(h, p), { alive: true, latency: 0, lastCheck: 0 }));

async function checkNode(host, port) {
  const start = Date.now();
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3000);
    const res = await fetch(`http://${host}:${port}/health`, { signal: controller.signal });
    clearTimeout(timeout);
    const alive = res.ok;
    const latency = Date.now() - start;
    nodeHealth.set(nodeKey(host, port), { alive, latency, lastCheck: Date.now() });
    return alive;
  } catch (e) {
    nodeHealth.set(nodeKey(host, port), { alive: false, latency: -1, lastCheck: Date.now() });
    return false;
  }
}

async function healthCheckAll() {
  const nodes = [...ALPHA_PORTS.map(p => [ALPHA_HOST, p]), ...BRAVO_PORTS.map(p => [BRAVO_HOST, p])];
  await Promise.all(nodes.map(([h, p]) => checkNode(h, p)));
}
setInterval(healthCheckAll, 5000);
healthCheckAll();

// ── ROUND-ROBIN ──
let rrIndex = 0;
function pickHealthyNode() {
  const alive = [];
  for (const [key, state] of nodeHealth) {
    if (state.alive) alive.push(key);
  }
  if (alive.length === 0) return null;
  rrIndex = (rrIndex + 1) % alive.length;
  const [host, port] = alive[rrIndex].split(':');
  return { host, port: parseInt(port) };
}

// ── CACHE ──
async function cacheGet(key) {
  if (!redisClient) return null;
  try { return await redisClient.get(key); } catch (e) { return null; }
}
async function cacheSet(key, value, ttl = CACHE_TTL) {
  if (!redisClient) return;
  try { await redisClient.setEx(key, ttl, value); } catch (e) {}
}

// ── RATE LIMIT ──
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 300,
  message: { error: 'Rate limit exceeded. Max 300 req/min.' }
});
app.use(limiter);

// ── CORS ──
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

// ── ENDPOINTS ──

app.get('/health', async (req, res) => {
  const nodes = {};
  for (const [key, state] of nodeHealth) {
    nodes[key] = { alive: state.alive, latency: state.latency, lastCheck: state.lastCheck };
  }
  const aliveCount = Object.values(nodes).filter(n => n.alive).length;
  res.json({
    gateway: 'ok',
    redis: redisClient ? 'connected' : 'disconnected',
    totalNodes: 18,
    aliveNodes: aliveCount,
    nodes
  });
});

app.get('/rest/blocks', async (req, res) => {
  const cacheKey = 'rest:blocks';
  const cached = await cacheGet(cacheKey);
  if (cached) return res.json(JSON.parse(cached));

  const node = pickHealthyNode();
  if (!node) return res.status(503).json({ error: 'No healthy validators' });

  try {
    const response = await fetch(`http://${node.host}:${node.port}/rest/blocks?limit=${req.query.limit || 20}`, {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' }
    });
    const data = await response.json();
    await cacheSet(cacheKey, JSON.stringify(data), 2);
    res.json(data);
  } catch (e) {
    res.status(502).json({ error: 'Validator error', detail: e.message });
  }
});

app.get('/rest/validators', async (req, res) => {
  const cacheKey = 'rest:validators';
  const cached = await cacheGet(cacheKey);
  if (cached) return res.json(JSON.parse(cached));

  const node = pickHealthyNode();
  if (!node) return res.status(503).json({ error: 'No healthy validators' });

  try {
    const response = await fetch(`http://${node.host}:${node.port}/rest/validators`, { method: 'GET' });
    const data = await response.json();
    await cacheSet(cacheKey, JSON.stringify(data), 5);
    res.json(data);
  } catch (e) {
    res.status(502).json({ error: 'Validator error', detail: e.message });
  }
});

app.get('/rest/shards', async (req, res) => {
  const cacheKey = 'rest:shards';
  const cached = await cacheGet(cacheKey);
  if (cached) return res.json(JSON.parse(cached));

  try {
    const [alpha, bravo] = await Promise.all([
      fetch(`http://${ALPHA_HOST}:${ALPHA_PORTS[0]}/rest/shards`).then(r => r.json()).catch(() => null),
      fetch(`http://${BRAVO_HOST}:${BRAVO_PORTS[0]}/rest/shards`).then(r => r.json()).catch(() => null)
    ]);
    const data = {
      totalShards: 6,
      alpha: alpha || { error: 'unreachable' },
      bravo: bravo || { error: 'unreachable' },
      nodesOnline: Object.values(Object.fromEntries(nodeHealth)).filter(n => n.alive).length
    };
    await cacheSet(cacheKey, JSON.stringify(data), 5);
    res.json(data);
  } catch (e) {
    res.status(502).json({ error: 'Shard aggregation failed', detail: e.message });
  }
});

app.get('/rest/network/stats', async (req, res) => {
  const cacheKey = 'rest:network:stats';
  const cached = await cacheGet(cacheKey);
  if (cached) return res.json(JSON.parse(cached));

  const node = pickHealthyNode();
  if (!node) return res.status(503).json({ error: 'No healthy validators' });

  try {
    const response = await fetch(`http://${node.host}:${node.port}/rest/network/stats`, { method: 'GET' });
    const data = await response.json();
    await cacheSet(cacheKey, JSON.stringify(data), 3);
    res.json(data);
  } catch (e) {
    res.status(502).json({ error: 'Validator error', detail: e.message });
  }
});

app.get('/rest/metrics', async (req, res) => {
  const cacheKey = 'rest:metrics';
  const cached = await cacheGet(cacheKey);
  if (cached) return res.json(JSON.parse(cached));

  try {
    const [prom3000, prom9100] = await Promise.all([
      fetch('http://localhost:3000/metrics').then(r => r.text()).catch(() => null),
      fetch('http://localhost:9100/metrics').then(r => r.text()).catch(() => null)
    ]);
    const data = {
      scrapedAt: new Date().toISOString(),
      prometheus3000: prom3000 ? 'connected' : 'unreachable',
      prometheus9100: prom9100 ? 'connected' : 'unreachable',
      nodesOnline: Object.values(Object.fromEntries(nodeHealth)).filter(n => n.alive).length,
      totalNodes: 18,
      uptime: process.uptime()
    };
    await cacheSet(cacheKey, JSON.stringify(data), 10);
    res.json(data);
  } catch (e) {
    res.status(502).json({ error: 'Metrics scrape failed', detail: e.message });
  }
});

app.post('/rpc', async (req, res) => {
  const node = pickHealthyNode();
  if (!node) return res.status(503).json({ error: 'No healthy validators available' });

  const body = req.body;
  const isViewCall = body.method && body.method.includes('View');
  const cacheKey = isViewCall ? `rpc:${body.method}:${JSON.stringify(body.params)}` : null;

  if (cacheKey) {
    const cached = await cacheGet(cacheKey);
    if (cached) {
      res.setHeader('X-Cache', 'HIT');
      return res.json(JSON.parse(cached));
    }
  }

  try {
    const response = await fetch(`http://${node.host}:${node.port}/rpc`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    const data = await response.json();
    if (cacheKey && data.result !== undefined) {
      await cacheSet(cacheKey, JSON.stringify(data), 2);
    }
    res.setHeader('X-Cache', cacheKey ? 'MISS' : 'SKIP');
    res.json(data);
  } catch (e) {
    res.status(502).json({ error: 'RPC proxy failed', detail: e.message, node: `${node.host}:${node.port}` });
  }
});

app.get('/ws', (req, res) => {
  res.status(426).json({ error: 'Use WebSocket protocol for /ws', upgradeTo: 'wss://api.synapticchain.xyz/ws' });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`SynapticChain API Gateway on port ${PORT}`);
  console.log(`Alpha: ${ALPHA_HOST}:${ALPHA_PORTS[0]}-${ALPHA_PORTS[ALPHA_PORTS.length-1]}`);
  console.log(`Bravo: ${BRAVO_HOST}:${BRAVO_PORTS[0]}-${BRAVO_PORTS[BRAVO_PORTS.length-1]}`);
  console.log(`Redis: ${redisClient ? 'enabled' : 'disabled'}`);
});

module.exports = app;
