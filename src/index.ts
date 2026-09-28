import { app } from './app.js';
import { env } from './config/env.js';
import { redis } from './config/redis.js';
import { prisma } from './config/prisma.js';
import { logger } from './config/logger.js';
import { seedDatabase } from './config/seeder.js';

async function bootstrap() {
  try {
    // 1. Connect Redis Client
    await redis.connect();
    logger.info("Connected to Redis Cache server successfully.");

    // 2. Connect PostgreSQL Client via Prisma
    await prisma.$connect();
    logger.info("Connected to PostgreSQL Database server successfully.");

    // 3. Auto Seed Database if empty (development/test only).
    // Production NEVER auto-seeds: demo records must not be created on a
    // live VPS no matter what state the database is in.
    if (env.NODE_ENV === 'production') {
      logger.info("Production environment detected; database auto-seeding is disabled.");
    } else {
      await seedDatabase();
    }

    // 4. Start listening
    const server = app.listen(env.PORT, () => {
      logger.info(`Athlete's POV Server is listening on http://localhost:${env.PORT}`);
      logger.info(`Admin Portal available at http://localhost:${env.PORT}/admin/login.html`);
    });

    // 5. Initialize WebSocket Server
    const { WebSocketService } = await import('./shared/services/websocket.js');
    WebSocketService.init(server);

    // 6. P2-1: pending-booking expiry sweeper (interval + Redis advisory lock,
    // safe under multi-instance deploys). Server-side only; no client needed.
    const { startExpiryJob } = await import('./shared/services/expiryJob.js');
    startExpiryJob({ intervalMs: env.BOOKING_EXPIRY_INTERVAL_MS, batchSize: env.BOOKING_EXPIRY_BATCH });
  } catch (err) {
    logger.error("Startup failed:", err);
    process.exit(1);
  }
}

bootstrap();
