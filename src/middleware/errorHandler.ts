import { Request, Response, NextFunction } from 'express';
import { AppError } from '../shared/utils/errors.js';
import { logger } from '../config/logger.js';

export function errorHandler(
  err: any,
  req: Request,
  res: Response,
  next: NextFunction
) {
  let statusCode = 500;
  let code = "INTERNAL_SERVER_ERROR";
  let message = "An unexpected error occurred.";
  let details: any = null;

  if (err instanceof AppError) {
    statusCode = err.statusCode;
    code = err.code;
    message = err.message;
    details = err.details;
  } else if (err instanceof Error) {
    // Never leak internal error text (SQL, Prisma internals, paths, secrets)
    // to API consumers. Full details stay in server logs below.
    logger.error(`${req.method} ${req.path} - Unhandled error: ${err.message}`, {
      stack: err.stack,
    });
  }

  logger.error(`${req.method} ${req.path} - Error: ${message}`, {
    stack: err.stack,
    details
  });

  return res.status(statusCode).json({
    success: false,
    error: {
      code,
      message,
      details
    }
  });
}

export default errorHandler;
