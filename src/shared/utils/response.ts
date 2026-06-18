import { Response } from 'express';

export function sendSuccess(res: Response, data: any = {}, status: number = 200) {
  return res.status(status).json({
    success: true,
    data
  });
}

export function sendPaginated(res: Response, data: any[], total: number, page: number, limit: number) {
  return res.status(200).json({
    success: true,
    data,
    meta: {
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit)
    }
  });
}
