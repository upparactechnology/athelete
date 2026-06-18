export function sendSuccess(res, data = {}, status = 200) {
    return res.status(status).json({
        success: true,
        data
    });
}
export function sendPaginated(res, data, total, page, limit) {
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
