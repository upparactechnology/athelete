import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import morgan from 'morgan';
import path from 'path';
import { fileURLToPath } from 'url';
import { env } from './config/env.js';
import { httpLogStream } from './config/logger.js';
import { adminRoutes } from './modules/admin/admin.routes.js';
import { clientRoutes } from './modules/client/client.routes.js';
import { errorHandler } from './middleware/errorHandler.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

// Security Hardening Middleware
app.use(helmet({
  contentSecurityPolicy: false // Disable CSP validation to permit visual tools/scripts locally
}));

// CORS Configuration
app.use(cors({
  origin: env.ALLOWED_ORIGINS === "*" ? "*" : env.ALLOWED_ORIGINS.split(","),
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization", "X-Admin-Role"]
}));

// Compression Middleware
app.use(compression());

// Request HTTP logger
app.use(morgan(":method :url :status :res[content-length] - :response-time ms", { stream: httpLogStream }));

// Webhook Raw parser routing
app.use('/api/payments/webhook', express.raw({ type: 'application/json' }));

// Parse request JSON payloads
app.use(express.json({ limit: "2mb" }));
app.use(express.urlencoded({ extended: true, limit: "2mb" }));

// Serve Static Admin Client files
app.use('/admin', express.static(path.join(__dirname, '../public/admin')));

// Mount administrative REST APIs
app.use('/api/admin', adminRoutes);

// Mount client REST APIs
app.use('/api', clientRoutes);

// Catch all unregistered API routes
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: {
      code: "NOT_FOUND",
      message: `Cannot ${req.method} ${req.path}`
    }
  });
});

// Mount Global Error Handling Middleware
app.use(errorHandler);

export { app };
export default app;
