export class AppError extends Error {
    statusCode;
    code;
    details;
    constructor(message, statusCode, code, details = null) {
        super(message);
        this.statusCode = statusCode;
        this.code = code;
        this.details = details;
        Object.setPrototypeOf(this, new.target.prototype);
    }
}
export class NotFoundError extends AppError {
    constructor(message = "Resource not found", details = null) {
        super(message, 404, "NOT_FOUND", details);
    }
}
export class ValidationError extends AppError {
    constructor(message = "Validation failed", details = null) {
        super(message, 400, "VALIDATION_ERROR", details);
    }
}
export class UnauthorizedError extends AppError {
    constructor(message = "Authentication failed", details = null) {
        super(message, 401, "AUTH_FAILED", details);
    }
}
export class ForbiddenError extends AppError {
    constructor(message = "Access forbidden", details = null) {
        super(message, 403, "FORBIDDEN", details);
    }
}
export class ConflictError extends AppError {
    constructor(message = "Resource conflict", code = "CONFLICT", details = null) {
        super(message, 409, code, details);
    }
}
