import { ForbiddenError, UnauthorizedError } from '../shared/utils/errors.js';
export function authorize(...allowedRoles) {
    return (req, res, next) => {
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
