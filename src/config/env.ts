import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

const envSchema = z.object({
  PORT: z.coerce.number().default(4000),
  DATABASE_URL: z.string(),
  REDIS_URL: z.string(),
  JWT_ACCESS_SECRET: z.string(),
  JWT_REFRESH_SECRET: z.string(),
  ADMIN_EMAIL: z.string().email(),
  ADMIN_PASSWORD_HASH: z.string(),
  ALLOWED_ORIGINS: z.string().default('*'),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  // Google Sign-In (verified server-side; never trust client-supplied email)
  GOOGLE_CLIENT_ID: z.string().optional(),
  GOOGLE_CLIENT_IDS: z.string().optional(), // comma-separated additional audiences
  // OTP behaviour. OTP_DEV_MODE=true returns the OTP in the API response for
  // local development ONLY and is rejected when NODE_ENV=production.
  OTP_DEV_MODE: z.enum(['true', 'false']).default('false'),
  OTP_RESEND_COOLDOWN_SECONDS: z.coerce.number().default(60),
  OTP_MAX_ATTEMPTS: z.coerce.number().default(5),
  // Razorpay. Env values take precedence over Redis system_settings.
  RAZORPAY_KEY_ID: z.string().optional(),
  RAZORPAY_KEY_SECRET: z.string().optional(),
  RAZORPAY_WEBHOOK_SECRET: z.string().optional(),
  // Explicit opt-in for simulated payments. NEVER enabled in production.
  ALLOW_MOCK_PAYMENTS: z.enum(['true', 'false']).default('false'),
  // P2-1: unpaid PENDING booking lifetime (minutes) before expiry releases slot.
  BOOKING_EXPIRY_MINUTES: z.coerce.number().default(30),
  BOOKING_EXPIRY_BATCH: z.coerce.number().default(100),
  BOOKING_EXPIRY_INTERVAL_MS: z.coerce.number().default(60_000),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error("Environment validation failed:", parsed.error.format());
  process.exit(1);
}

export const env = parsed.data;
export type Env = z.infer<typeof envSchema>;
