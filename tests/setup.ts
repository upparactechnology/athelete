// Test setup: dummy env so src/config/env.ts validation passes on import.
// No real credentials; never used for network/DB access in unit tests.
process.env.DATABASE_URL ??= 'postgresql://test:test@localhost:5432/test';
process.env.REDIS_URL ??= 'redis://localhost:6379';
process.env.JWT_ACCESS_SECRET ??= 'test-access-secret-0123456789abcdef';
process.env.JWT_REFRESH_SECRET ??= 'test-refresh-secret-0123456789abcdef';
process.env.ADMIN_EMAIL ??= 'admin@example.com';
process.env.ADMIN_PASSWORD_HASH ??= 'test-hash';
process.env.NODE_ENV ??= 'test';
