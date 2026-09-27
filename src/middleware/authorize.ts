import { Response, NextFunction } from 'express';
import { ForbiddenError, UnauthorizedError } from '../shared/utils/errors.js';
import { AuthRequest, UserRole } from '../shared/types/index.js';

export function authorize(...allowedRoles: UserRole[]) {
  return (req: AuthRequest, res: Response, next: NextFunction) => {
    if (!req.user) {
      return next(new UnauthorizedError("User not authenticated"));
    }

    const { role } = req.user;

    if (!allowedRoles.includes(role)) {
      return next(new ForbiddenError("You do not have permission to access this resource"));
    }

    // The JWT role is the authority. No client-controlled header may grant
    // or escalate privileges (previously X-Admin-Role was trusted).
    next();
  };
}

export default authorize;
