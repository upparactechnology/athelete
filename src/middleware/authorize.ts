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

    if (role === "admin") {
      const adminHeader = req.headers["x-admin-role"];
      if (adminHeader !== "admin") {
        return next(new ForbiddenError("Admin access requires matching X-Admin-Role header"));
      }
    }

    next();
  };
}

export default authorize;
