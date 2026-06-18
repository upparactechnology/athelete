import { Request } from 'express';

export type UserRole = 'user' | 'partner' | 'admin';

export interface JwtAccessPayload {
  sub: string;
  role: UserRole;
  status: string;
}

export interface AuthRequest extends Request {
  user?: {
    id: string;
    role: UserRole;
    status: string;
  };
}

export interface PaginatedQuery {
  page?: string;
  limit?: string;
}
