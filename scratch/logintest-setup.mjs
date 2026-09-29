// Local fixtures for POST /api/auth/login test. TEST DATA ONLY.
import dotenv from 'dotenv';
dotenv.config();
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();
await prisma.partner.deleteMany({ where: { phone_number: { contains: 'logintest' } } }).catch(() => undefined);
await prisma.user.deleteMany({ where: { phone_number: { contains: 'logintest' } } }).catch(() => undefined);

await prisma.partner.create({
  data: {
    phone_number: 'logintest-partner-001',
    email: 'logintest-partner-001@example.com',
    kyc_status: 'verified',
    password_hash: await bcrypt.hash('password123', 10),
  },
});
// Google-created partner: no password.
await prisma.partner.create({
  data: { phone_number: 'logintest-google-001@example.com', email: 'logintest-google-001@example.com', kyc_status: 'verified' },
});
// Deleted partner with (old) password still set.
await prisma.partner.create({
  data: {
    phone_number: 'deleted-partner-logintest-gone',
    email: 'deleted-partner-logintest-gone@athletepov.com',
    kyc_status: 'deleted',
    password_hash: await bcrypt.hash('password123', 10),
  },
});
await prisma.user.create({
  data: { phone_number: 'logintest-user-001', email: 'logintest-user-001@example.com', name: 'Login Test', status: 'Active', password_hash: await bcrypt.hash('password123', 10) },
});
console.log('LOGIN FIXTURES OK');
await prisma.$disconnect();
