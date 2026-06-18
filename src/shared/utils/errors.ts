export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: string;
  public readonly details: any;

  constructor(message: string, statusCode: number, code: string, details: any = null) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

export class NotFoundError extends AppError {
  constructor(message: string = "Resource not found", details: any = null) {
    super(message, 404, "NOT_FOUND", details);
  }
}

export class ValidationError extends AppError {
  constructor(message: string = "Validation failed", details: any = null) {
    super(message, 400, "VALIDATION_ERROR", details);
  }
}

export class UnauthorizedError extends AppError {
  constructor(message: string = "Authentication failed", details: any = null) {
    super(message, 401, "AUTH_FAILED", details);
  }
}

export class ForbiddenError extends AppError {
  constructor(message: string = "Access forbidden", details: any = null) {
    super(message, 403, "FORBIDDEN", details);
  }
}

export class ConflictError extends AppError {
  constructor(message: string = "Resource conflict", code: string = "CONFLICT", details: any = null) {
    super(message, 409, code, details);
  }
}
