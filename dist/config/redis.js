import { createClient } from 'redis';
import { env } from './env.js';
export const redis = createClient({
    url: env.REDIS_URL,
});
redis.on("error", (err) => console.error("Redis Client Error", err));
export const RedisKeys = {
    slotLock: (slotId) => `slot:lock:${slotId}`,
    slotsAvail: (venueId, date) => `slots:avail:${venueId}:${date}`,
    featuredVenues: () => 'featured_venues',
    otp: (phone) => `otp:${phone}`,
    otpAttempts: (phone) => `otp:attempts:${phone}`,
};
export default redis;
