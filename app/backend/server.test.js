// ─────────────────────────────────────────────────────────────────────────────
// FintechBank API – Test Suite
// ─────────────────────────────────────────────────────────────────────────────
const request = require('supertest');
const app = require('./server');

let authToken = '';
let userId = '';

// ── Auth Tests ────────────────────────────────────────────────────────────────
describe('Auth Endpoints', () => {
  test('POST /api/auth/login – success with valid credentials', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'shubham@fintech.dev', password: 'Password@123' });
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('token');
    expect(res.body).toHaveProperty('user');
    expect(res.body.user.email).toBe('shubham@fintech.dev');
    authToken = res.body.token;
    userId = res.body.user.id;
  });

  test('POST /api/auth/login – fails with wrong password', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'shubham@fintech.dev', password: 'wrongpass' });
    expect(res.status).toBe(401);
    expect(res.body).toHaveProperty('error');
  });

  test('POST /api/auth/login – fails with missing fields', async () => {
    const res = await request(app)
      .post('/api/auth/login')
      .send({ email: 'shubham@fintech.dev' });
    expect(res.status).toBe(400);
  });

  test('POST /api/auth/register – creates new user', async () => {
    const res = await request(app)
      .post('/api/auth/register')
      .send({ name: 'Test User', email: `test_${Date.now()}@fintech.dev`, password: 'Test@12345' });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('user');
  });

  test('GET /api/auth/me – returns current user with valid token', async () => {
    const res = await request(app)
      .get('/api/auth/me')
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    expect(res.body.email).toBe('shubham@fintech.dev');
  });

  test('GET /api/auth/me – 401 without token', async () => {
    const res = await request(app).get('/api/auth/me');
    expect(res.status).toBe(401);
  });
});

// ── Account Tests ─────────────────────────────────────────────────────────────
describe('Account Endpoints', () => {
  test('GET /api/accounts – returns user accounts', async () => {
    const res = await request(app)
      .get('/api/accounts')
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('accounts');
    expect(Array.isArray(res.body.accounts)).toBe(true);
    expect(res.body.accounts.length).toBeGreaterThan(0);
  });

  test('GET /api/accounts – 401 without token', async () => {
    const res = await request(app).get('/api/accounts');
    expect(res.status).toBe(401);
  });
});

// ── Transaction Tests ─────────────────────────────────────────────────────────
describe('Transaction Endpoints', () => {
  test('GET /api/transactions – returns transactions', async () => {
    const res = await request(app)
      .get('/api/transactions')
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('transactions');
    expect(Array.isArray(res.body.transactions)).toBe(true);
  });

  test('POST /api/transactions/transfer – transfers funds', async () => {
    const accountsRes = await request(app)
      .get('/api/accounts')
      .set('Authorization', `Bearer ${authToken}`);
    const fromAccount = accountsRes.body.accounts[0];

    const res = await request(app)
      .post('/api/transactions/transfer')
      .set('Authorization', `Bearer ${authToken}`)
      .send({
        fromAccountId: fromAccount.id,
        toAccountNumber: '****2209',
        amount: 100,
        description: 'Test transfer',
      });
    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('transaction');
    expect(res.body.transaction.status).toBe('completed');
  });

  test('POST /api/transactions/transfer – fails with insufficient funds', async () => {
    const accountsRes = await request(app)
      .get('/api/accounts')
      .set('Authorization', `Bearer ${authToken}`);
    const fromAccount = accountsRes.body.accounts[0];

    const res = await request(app)
      .post('/api/transactions/transfer')
      .set('Authorization', `Bearer ${authToken}`)
      .send({
        fromAccountId: fromAccount.id,
        toAccountNumber: '****2209',
        amount: 99999999,
        description: 'Too much',
      });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/insufficient/i);
  });
});

// ── Dashboard Tests ───────────────────────────────────────────────────────────
describe('Dashboard Endpoints', () => {
  test('GET /api/dashboard/stats – returns stats', async () => {
    const res = await request(app)
      .get('/api/dashboard/stats')
      .set('Authorization', `Bearer ${authToken}`);
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('totalBalance');
    expect(res.body).toHaveProperty('totalAccounts');
    expect(res.body).toHaveProperty('recentTransactions');
  });
});

// ── Health / Metrics ──────────────────────────────────────────────────────────
describe('Health & Metrics', () => {
  test('GET /health – returns healthy status', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('healthy');
    expect(res.body).toHaveProperty('uptime');
  });

  test('GET /metrics – returns system metrics', async () => {
    const res = await request(app).get('/metrics');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('uptime_seconds');
    expect(res.body).toHaveProperty('memory');
  });
});

// ── Security Tests ────────────────────────────────────────────────────────────
describe('Security', () => {
  test('Response has security headers from Helmet', async () => {
    const res = await request(app).get('/health');
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['x-frame-options']).toBeDefined();
  });

  test('Invalid JWT returns 401', async () => {
    const res = await request(app)
      .get('/api/accounts')
      .set('Authorization', 'Bearer invalid.jwt.token');
    expect(res.status).toBe(401);
  });

  test('Admin route blocked for non-admin', async () => {
    // Login as non-admin user
    const loginRes = await request(app)
      .post('/api/auth/login')
      .send({ email: 'priya@fintech.dev', password: 'Password@123' });
    const userToken = loginRes.body.token;
    const res = await request(app)
      .get('/api/admin/users')
      .set('Authorization', `Bearer ${userToken}`);
    expect(res.status).toBe(403);
  });

  test('404 for unknown routes', async () => {
    const res = await request(app).get('/api/nonexistent');
    expect(res.status).toBe(404);
  });
});
