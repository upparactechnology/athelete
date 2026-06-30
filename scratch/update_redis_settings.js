import { redis } from '../dist/config/redis.js';

async function update() {
  try {
    await redis.connect();
    const data = await redis.get('system_settings');
    let settings = data ? JSON.parse(data) : {};

    settings.smtpHost = "smtp.gmail.com";
    settings.smtpPort = 587;
    settings.smtpUser = "hetshah6312@gmail.com";
    settings.smtpPass = "glep exwm zkcy muyp";
    settings.smtpSecure = false; // Must be false for 587
    settings.smtpFrom = "noreply@athelte.com";
    settings.useSmtpForOtp = true;

    await redis.set('system_settings', JSON.stringify(settings));
    console.log("Redis system_settings updated successfully:", settings);
    await redis.disconnect();
  } catch (err) {
    console.error("Update failed:", err);
  }
}

update();
