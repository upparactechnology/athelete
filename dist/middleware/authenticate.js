import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { UnauthorizedError } from '../shared/utils/errors.js';
export function authenticate(req, res, next) {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
        return next(new UnauthorizedError("No authentication token provided"));
    }
    const token = authHeader.split(" ")[1];
    if (!token) {
        return next(new UnauthorizedError("Access token is missing"));
    }
    try {
        const payload = jwt.verify(token, env.JWT_ACCESS_SECRET);
        req.user = {
            id: payload.sub,
            role: payload.role,
            status: payload.status
        };
        next();
    }
    catch (err) {
        return next(new UnauthorizedError("Invalid or expired access token"));
    }
}
export default authenticate;
