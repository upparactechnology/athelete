import rateLimit from 'express-rate-limit';

/** Brute-force protection for OTP + auth endpoints (P0). */

function limiter(windowMs: number, limit: number) {
  return rateLimit({
    windowMs,
    limit,
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      success: false,
      error: { code: 'RATE_LIMITED', message: 'Too many requests. Please try again later.' },
    },
  });
}

/** OTP requests: max 5 per 10 minutes per IP. */
export const otpRequestLimiter = limiter(10 * 60 * 1000, 5);

/** OTP verification attempts: max 10 per 10 minutes per IP. */
export const otpVerifyLimiter = limiter(10 * 60 * 1000, 10);

/** Google login attempts: max 20 per 10 minutes per IP. */
export const googleLoginLimiter = limiter(10 * 60 * 1000, 20);

/** Payment verification: max 30 per 10 minutes per IP. */
export const paymentVerifyLimiter = limiter(10 * 60 * 1000, 30);
