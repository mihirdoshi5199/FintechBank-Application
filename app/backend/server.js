const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = process.env.PORT || 4000;
const JWT_SECRET = process.env.JWT_SECRET || 'fintech-super-secret-key-change-in-prod';

// ─── Security Middleware ───────────────────────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'", "fonts.googleapis.com"],
      fontSrc: ["'self'", "fonts.gstatic.com"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:"],
    },
  },
  hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
}));

app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  credentials: true,
}));

app.use(express.json({ limit: '10kb' }));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { error: 'Too many requests, please try again later.' },
  standardHeaders: true,
  legacyHeaders: false,
});
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { error: 'Too many login attempts.' },
});

app.use('/api/', limiter);
app.use('/api/auth/', authLimiter);

// ─── In-Memory Database ────────────────────────────────────────────────────────
const db = {
  users: [
    {
      id: 'usr-001',
      name: 'Shubham Sharma',
      email: 'shubham@fintech.dev',
      password: bcrypt.hashSync('Password@123', 10),
      role: 'admin',
      createdAt: new Date('2024-01-15').toISOString(),
    },
    {
      id: 'usr-002',
      name: 'Priya Patel',
      email: 'priya@fintech.dev',
      password: bcrypt.hashSync('Password@123', 10),
      role: 'user',
      createdAt: new Date('2024-03-20').toISOString(),
    },
  ],
  accounts: [
    { id: 'acc-001', userId: 'usr-001', type: 'savings', balance: 125000.50, currency: 'INR', accountNumber: '****4521', status: 'active' },
    { id: 'acc-002', userId: 'usr-001', type: 'current', balance: 850000.00, currency: 'INR', accountNumber: '****8834', status: 'active' },
    { id: 'acc-003', userId: 'usr-002', type: 'savings', balance: 45000.75, currency: 'INR', accountNumber: '****2209', status: 'active' },
  ],
  transactions: [
    { id: 'txn-001', fromAccountId: 'acc-001', toAccountId: 'acc-003', amount: 5000, type: 'transfer', description: 'Monthly rent', status: 'completed', createdAt: new Date(Date.now() - 86400000 * 2).toISOString() },
    { id: 'txn-002', fromAccountId: null, toAccountId: 'acc-001', amount: 50000, type: 'credit', description: 'Salary deposit', status: 'completed', createdAt: new Date(Date.now() - 86400000 * 5).toISOString() },
    { id: 'txn-003', fromAccountId: 'acc-001', toAccountId: null, amount: 2500, type: 'debit', description: 'Utility bill payment', status: 'completed', createdAt: new Date(Date.now() - 86400000 * 1).toISOString() },
    { id: 'txn-004', fromAccountId: 'acc-002', toAccountId: 'acc-001', amount: 100000, type: 'transfer', description: 'Investment fund', status: 'completed', createdAt: new Date(Date.now() - 86400000 * 7).toISOString() },
    { id: 'txn-005', fromAccountId: null, toAccountId: 'acc-002', amount: 200000, type: 'credit', description: 'Business revenue', status: 'completed', createdAt: new Date(Date.now() - 86400000 * 10).toISOString() },
  ],
  deploymentLogs: [],
};

// ─── Auth Middleware ───────────────────────────────────────────────────────────
const authenticate = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  try {
    const token = authHeader.split(' ')[1];
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
};

// ─── Health Check ──────────────────────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'fintech-banking-api',
    version: process.env.APP_VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

app.get('/metrics', (req, res) => {
  const memUsage = process.memoryUsage();
  res.json({
    uptime_seconds: process.uptime(),
    memory: {
      rss_mb: (memUsage.rss / 1024 / 1024).toFixed(2),
      heap_used_mb: (memUsage.heapUsed / 1024 / 1024).toFixed(2),
      heap_total_mb: (memUsage.heapTotal / 1024 / 1024).toFixed(2),
    },
    users_count: db.users.length,
    accounts_count: db.accounts.length,
    transactions_count: db.transactions.length,
  });
});

// ─── Auth Routes ───────────────────────────────────────────────────────────────
app.post('/api/auth/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'Email and password required' });

  const user = db.users.find(u => u.email === email);
  if (!user || !(await bcrypt.compare(password, user.password))) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const token = jwt.sign(
    { id: user.id, email: user.email, role: user.role },
    JWT_SECRET,
    { expiresIn: '8h' }
  );

  const { password: _, ...safeUser } = user;
  res.json({ token, user: safeUser, expiresIn: '8h' });
});

app.post('/api/auth/register', async (req, res) => {
  const { name, email, password } = req.body;
  if (!name || !email || !password) return res.status(400).json({ error: 'All fields required' });
  if (db.users.find(u => u.email === email)) return res.status(409).json({ error: 'Email already registered' });

  const hashedPassword = await bcrypt.hash(password, 10);
  const newUser = { id: uuidv4(), name, email, password: hashedPassword, role: 'user', createdAt: new Date().toISOString() };
  db.users.push(newUser);

  const accountId = uuidv4();
  db.accounts.push({
    id: accountId, userId: newUser.id, type: 'savings',
    balance: 1000.00, currency: 'INR',
    accountNumber: '****' + Math.floor(1000 + Math.random() * 9000),
    status: 'active',
  });

  const { password: _, ...safeUser } = newUser;
  res.status(201).json({ message: 'Registration successful', user: safeUser });
});

app.get('/api/auth/me', authenticate, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  const { password: _, ...safeUser } = user;
  res.json(safeUser);
});

// ─── Account Routes ────────────────────────────────────────────────────────────
app.get('/api/accounts', authenticate, (req, res) => {
  const accounts = db.accounts.filter(a => a.userId === req.user.id);
  res.json({ accounts, total: accounts.reduce((s, a) => s + a.balance, 0) });
});

app.get('/api/accounts/:id', authenticate, (req, res) => {
  const account = db.accounts.find(a => a.id === req.params.id && a.userId === req.user.id);
  if (!account) return res.status(404).json({ error: 'Account not found' });
  res.json(account);
});

// ─── Transaction Routes ────────────────────────────────────────────────────────
app.get('/api/transactions', authenticate, (req, res) => {
  const userAccounts = db.accounts.filter(a => a.userId === req.user.id).map(a => a.id);
  const transactions = db.transactions
    .filter(t => userAccounts.includes(t.fromAccountId) || userAccounts.includes(t.toAccountId))
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  res.json({ transactions, count: transactions.length });
});

app.post('/api/transactions/transfer', authenticate, (req, res) => {
  const { fromAccountId, toAccountNumber, amount, description } = req.body;
  if (!fromAccountId || !toAccountNumber || !amount || amount <= 0) {
    return res.status(400).json({ error: 'Invalid transfer details' });
  }

  const fromAccount = db.accounts.find(a => a.id === fromAccountId && a.userId === req.user.id);
  if (!fromAccount) return res.status(404).json({ error: 'Source account not found' });
  if (fromAccount.balance < amount) return res.status(400).json({ error: 'Insufficient funds' });

  const toAccount = db.accounts.find(a => a.accountNumber === toAccountNumber);
  if (!toAccount) return res.status(404).json({ error: 'Destination account not found' });

  fromAccount.balance -= Number(amount);
  toAccount.balance += Number(amount);

  const txn = {
    id: 'txn-' + uuidv4().slice(0, 8),
    fromAccountId,
    toAccountId: toAccount.id,
    amount: Number(amount),
    type: 'transfer',
    description: description || 'Transfer',
    status: 'completed',
    createdAt: new Date().toISOString(),
  };
  db.transactions.push(txn);
  res.status(201).json({ message: 'Transfer successful', transaction: txn });
});

// ─── Dashboard Stats ───────────────────────────────────────────────────────────
app.get('/api/dashboard/stats', authenticate, (req, res) => {
  const userAccounts = db.accounts.filter(a => a.userId === req.user.id);
  const accountIds = userAccounts.map(a => a.id);
  const userTxns = db.transactions.filter(
    t => accountIds.includes(t.fromAccountId) || accountIds.includes(t.toAccountId)
  );

  const totalCredit = userTxns.filter(t => t.type === 'credit' || (t.type === 'transfer' && accountIds.includes(t.toAccountId)))
    .reduce((s, t) => s + t.amount, 0);
  const totalDebit = userTxns.filter(t => t.type === 'debit' || (t.type === 'transfer' && accountIds.includes(t.fromAccountId)))
    .reduce((s, t) => s + t.amount, 0);

  res.json({
    totalBalance: userAccounts.reduce((s, a) => s + a.balance, 0),
    totalAccounts: userAccounts.length,
    totalTransactions: userTxns.length,
    totalCredit,
    totalDebit,
    recentTransactions: userTxns.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)).slice(0, 5),
  });
});

// ─── Deployment Status Routes ──────────────────────────────────────────────────
app.get('/api/deployments/status', authenticate, (req, res) => {
  const deployments = [
    { id: 1, name: 'Secure VPS Hosting', status: 'active', strategy: 'SSH Hardening', uptime: '99.98%', region: 'ap-south-1' },
    { id: 2, name: 'Nginx Reverse Proxy', status: 'active', strategy: 'Security Headers', uptime: '99.99%', region: 'ap-south-1' },
    { id: 3, name: 'Docker Microservices', status: 'active', strategy: 'Optimized Builds', uptime: '99.95%', region: 'ap-south-1' },
    { id: 4, name: 'Self-Hosted Registry', status: 'active', strategy: 'Private Images', uptime: '99.90%', region: 'ap-south-1' },
    { id: 5, name: 'CI/CD Automation', status: 'active', strategy: 'GitHub Actions', uptime: '99.97%', region: 'global' },
    { id: 6, name: 'Private Runners', status: 'active', strategy: 'Self-Hosted Speed', uptime: '99.85%', region: 'ap-south-1' },
    { id: 7, name: 'Canary Releases', status: 'active', strategy: 'Traffic Splitting', uptime: '99.99%', region: 'ap-south-1' },
    { id: 8, name: 'Full-Stack Monitoring', status: 'active', strategy: 'Grafana/Prometheus', uptime: '99.93%', region: 'ap-south-1' },
    { id: 9, name: 'Secrets Management', status: 'active', strategy: 'Vault/Env Vars', uptime: '100%', region: 'ap-south-1' },
    { id: 10, name: 'Production-Grade Launch', status: 'active', strategy: 'Final Stage', uptime: '99.99%', region: 'ap-south-1' },
  ];
  res.json({ deployments, environment: process.env.NODE_ENV || 'development' });
});

// ─── Admin Routes ──────────────────────────────────────────────────────────────
app.get('/api/admin/users', authenticate, (req, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'Forbidden' });
  const users = db.users.map(({ password: _, ...u }) => u);
  res.json({ users, count: users.length });
});

// 404 handler
app.use((req, res) => res.status(404).json({ error: 'Route not found' }));

// Error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`🚀 FintechBank API running on port ${PORT}`);
    console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
  });
}

module.exports = app;
