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
        // 3. Auto Seed Database if empty
        await seedDatabase();
        // 4. Start listening
        const server = app.listen(env.PORT, () => {
            logger.info(`Athlete's POV Server is listening on http://localhost:${env.PORT}`);
            logger.info(`Admin Portal available at http://localhost:${env.PORT}/admin/login.html`);
        });
        // 5. Initialize WebSocket Server
        const { WebSocketService } = await import('./shared/services/websocket.js');
        WebSocketService.init(server);
    }
    catch (err) {
        logger.error("Startup failed:", err);
        process.exit(1);
    }
}
bootstrap();
