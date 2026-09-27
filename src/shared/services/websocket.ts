import { WebSocketServer, WebSocket } from 'ws';
import { Server } from 'http';
import jwt from 'jsonwebtoken';
import { logger } from '../../config/logger.js';
import { prisma } from '../../config/prisma.js';
import { env } from '../../config/env.js';
import { JwtAccessPayload, UserRole } from '../../shared/types/index.js';

interface AuthedSocket {
  ws: WebSocket;
  userId: string;
  role: UserRole;
}

/** P2-8: live account-status gate for socket upgrades. */
async function checkSocketIdentity(payload: JwtAccessPayload): Promise<boolean> {
  try {
    if (payload.role === 'user') {
      const user = await prisma.user.findUnique({ where: { user_id: payload.sub }, select: { status: true } });
      return !!user && user.status === 'Active';
    }
    if (payload.role === 'partner') {
      const partner = await prisma.partner.findUnique({ where: { partner_id: payload.sub }, select: { kyc_status: true } });
      return !!partner && (partner as any).kyc_status !== 'deleted';
    }
    if (payload.role === 'admin') return true;
    return false;
  } catch {
    return false;
  }
}

/**
 * Authenticated WebSocket service (P0).
 * - The HTTP upgrade MUST carry a valid JWT (`?token=` or Authorization
 *   header). Invalid/expired tokens are rejected during upgrade.
 * - Each connection is bound to { userId, role }.
 * - Private data is delivered only to its owner via targeted emits.
 * - `broadcast` is retained ONLY for genuinely public events (slot
 *   availability, public settings subset) and must never carry PII,
 *   financial, or per-user/per-partner private payloads.
 */
export class WebSocketService {
  private static wss: WebSocketServer | null = null;
  private static clients: Set<AuthedSocket> = new Set();

  public static init(server: Server) {
    this.wss = new WebSocketServer({ noServer: true });

    server.on('upgrade', (request, socket, head) => {
      const url = new URL(request.url || '', `http://${request.headers.host}`);
      if (url.pathname !== '/ws') {
        socket.destroy();
        return;
      }
      const token =
        url.searchParams.get('token') ||
        (request.headers.authorization || '').replace(/^Bearer\s+/i, '');
      let payload: JwtAccessPayload;
      try {
        if (!token) throw new Error('missing token');
        payload = jwt.verify(token, env.JWT_ACCESS_SECRET) as JwtAccessPayload;
        if (!payload.sub || !payload.role) throw new Error('invalid payload');
      } catch (_) {
        logger.warn('Rejected unauthenticated WebSocket upgrade attempt.');
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }
      // P2-8: reject deleted/deactivated accounts at connect time (async DB check).
      checkSocketIdentity(payload).then((active) => {
        if (!active) {
          logger.warn('Rejected WebSocket upgrade for inactive/deleted account.');
          try {
            socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
          } catch { /* ignore */ }
          socket.destroy();
          return;
        }
        this.wss?.handleUpgrade(request, socket, head, (ws) => {
          this.wss?.emit('connection', ws, request, payload);
        });
      }).catch(() => {
        try {
          socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        } catch { /* ignore */ }
        socket.destroy();
      });
    });

    this.wss.on('connection', (ws: WebSocket, _request: any, payload?: JwtAccessPayload) => {
      if (!payload) {
        ws.close(4401, 'Unauthorized');
        return;
      }
      const client: AuthedSocket = { ws, userId: payload.sub, role: payload.role };
      this.clients.add(client);
      logger.info('New authenticated WebSocket connection established.');

      ws.on('message', async (message: string) => {
        try {
          const parsed = JSON.parse(message);
          if (parsed.type === 'ping') {
            ws.send(JSON.stringify({ type: 'pong' }));
          } else if (parsed.type === 'chat_message') {
            // Sender identity comes from the authenticated socket, never the payload.
            const { recipientId, text } = parsed.data || {};
            if (!recipientId || typeof text !== 'string' || !text.trim() || text.length > 2000) {
              ws.send(JSON.stringify({ type: 'error', data: { message: 'Invalid chat message' } }));
              return;
            }
            if (recipientId === client.userId) {
              ws.send(JSON.stringify({ type: 'error', data: { message: 'Cannot message yourself' } }));
              return;
            }
            const chatMsg = await prisma.chatMessage.create({
              data: {
                sender_id: client.userId,
                sender_role: client.role,
                recipient_id: String(recipientId),
                text: text.trim()
              }
            });
            // Deliver ONLY to the two participants.
            WebSocketService.emitToUser(chatMsg.sender_id, 'chat_message', chatMsg);
            WebSocketService.emitToUser(chatMsg.recipient_id, 'chat_message', chatMsg);
          }
        } catch (err) {
          logger.error('WebSocket message parsing error:', err);
        }
      });


      ws.on('close', () => {
        this.clients.delete(client);
        logger.info('WebSocket connection closed.');
      });

      ws.on('error', (err) => {
        logger.error('WebSocket client error:', err);
        this.clients.delete(client);
      });
    });

    logger.info('WebSocket Server initialized on path /ws');
  }

  /**
   * Public broadcast ONLY (slot availability grids, non-sensitive counters).
   * Callers must not pass bookings, payments, PII, or settings-with-secrets.
   */
  public static broadcast(type: string, data: any) {
    if (!this.wss) {
      logger.warn('WebSocket server not initialized, skipping broadcast.');
      return;
    }
    const payload = JSON.stringify({ type, data });
    this.clients.forEach((client) => {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(payload);
      }
    });
  }

  /** Targeted delivery to one authenticated identity (all its sockets). */
  public static emitToUser(userId: string, type: string, data: any) {
    const payload = JSON.stringify({ type, data });
    this.clients.forEach((client) => {
      if (client.userId === userId && client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(payload);
      }
    });
  }

  /** Targeted delivery to every connection holding a role. */
  public static emitToRole(role: UserRole, type: string, data: any) {
    const payload = JSON.stringify({ type, data });
    this.clients.forEach((client) => {
      if (client.role === role && client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(payload);
      }
    });
  }
}
