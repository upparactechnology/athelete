import { WebSocketServer, WebSocket } from 'ws';
import { logger } from '../../config/logger.js';
import { prisma } from '../../config/prisma.js';
export class WebSocketService {
    static wss = null;
    static clients = new Set();
    static init(server) {
        this.wss = new WebSocketServer({ noServer: true });
        server.on('upgrade', (request, socket, head) => {
            const pathname = new URL(request.url || '', `http://${request.headers.host}`).pathname;
            if (pathname === '/ws') {
                this.wss?.handleUpgrade(request, socket, head, (ws) => {
                    this.wss?.emit('connection', ws, request);
                });
            }
            else {
                socket.destroy();
            }
        });
        this.wss.on('connection', (ws) => {
            this.clients.add(ws);
            logger.info('New WebSocket connection established.');
            ws.on('message', async (message) => {
                try {
                    const parsed = JSON.parse(message);
                    if (parsed.type === 'ping') {
                        ws.send(JSON.stringify({ type: 'pong' }));
                    }
                    else if (parsed.type === 'chat_message') {
                        const { senderId, senderRole, recipientId, text } = parsed.data;
                        const chatMsg = await prisma.chatMessage.create({
                            data: {
                                sender_id: senderId,
                                sender_role: senderRole,
                                recipient_id: recipientId,
                                text: text
                            }
                        });
                        // Broadcast the newly created message to everyone
                        WebSocketService.broadcast('chat_message', chatMsg);
                    }
                }
                catch (err) {
                    logger.error('WebSocket message parsing error:', err);
                }
            });
            ws.on('close', () => {
                this.clients.delete(ws);
                logger.info('WebSocket connection closed.');
            });
            ws.on('error', (err) => {
                logger.error('WebSocket client error:', err);
                this.clients.delete(ws);
            });
        });
        logger.info('WebSocket Server initialized on path /ws');
    }
    static broadcast(type, data) {
        if (!this.wss) {
            logger.warn('WebSocket server not initialized, skipping broadcast.');
            return;
        }
        const payload = JSON.stringify({ type, data });
        this.clients.forEach((client) => {
            if (client.readyState === WebSocket.OPEN) {
                client.send(payload);
            }
        });
    }
}
