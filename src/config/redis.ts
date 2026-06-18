import { createClient } from 'redis';
import { env } from './env.js';

export const redis = createClient({
  url: env.REDIS_URL,
});

redis.on("error", (err) => console.error("Redis Client Error", err));

export const RedisKeys = {
  slotLock: (slotId: string) => `slot:lock:${slotId}`,
  slotsAvail: (venueId: string, date: string) => `slots:avail:${venueId}:${date}`,
  featuredVenues: () => 'featured_venues',
  otp: (phone: string) => `otp:${phone}`,
  otpAttempts: (phone: string) => `otp:attempts:${phone}`,
};
export default redis;
