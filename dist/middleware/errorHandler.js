import { AppError } from '../shared/utils/errors.js';
import { logger } from '../config/logger.js';
export function errorHandler(err, req, res, next) {
    let statusCode = 500;
    let code = "INTERNAL_SERVER_ERROR";
    let message = "An unexpected error occurred.";
    let details = null;
    if (err instanceof AppError) {
        statusCode = err.statusCode;
        code = err.code;
        message = err.message;
        details = err.details;
    }
    else if (err instanceof Error) {
        message = err.message;
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
