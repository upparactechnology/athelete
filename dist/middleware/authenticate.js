import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { UnauthorizedError } from '../shared/utils/errors.js';
import { prisma } from '../config/prisma.js';
export async function authenticate(req, res, next) {
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
        if (payload.role === 'user') {
            const user = await prisma.user.findUnique({ where: { user_id: payload.sub } });
            if (!user) {
                return next(new UnauthorizedError("User profile no longer exists. Please log in again."));
            }
        }
        else if (payload.role === 'partner') {
            const partner = await prisma.partner.findUnique({ where: { partner_id: payload.sub } });
            if (!partner) {
                return next(new UnauthorizedError("Partner profile no longer exists. Please log in again."));
            }
        }
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
