import { v4 as uuid } from 'uuid';
import { logger } from '../utils/logger.js';

/**
 * OpenAI-compatible HTTP API for ElevenLabs Custom LLM integration.
 *
 * ElevenLabs Agents can be configured with a "Custom LLM" endpoint that
 * follows the OpenAI chat completions format. This module adds two routes
 * to the existing HTTPS server used for WebSocket connections:
 *
 *   POST /v1/chat/completions   — OpenAI-compatible completion endpoint
 *                                  that forwards the user message to the
 *                                  current OpenClaw/NemoClaw agent.
 *   GET  /v1/models             — Returns the active agent as a "model".
 *
 * Auth: Bearer token. Use the same relay authToken as the iOS app.
 *
 * Supports both streaming (text/event-stream) and non-streaming responses.
 */
export function attachHttpApi(httpsServer, { bridge, authToken, config }) {
    // Intercept requests BEFORE the WebSocket upgrade handler sees them.
    // The existing HTTPS server is shared with the WS server (ws module
    // hooks into the 'upgrade' event). Regular HTTP requests flow through
    // the server's 'request' event.
    httpsServer.on('request', async (req, res) => {
        const url = new URL(req.url, `https://${req.headers.host}`);

        // CORS
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

        if (req.method === 'OPTIONS') {
            res.writeHead(204);
            res.end();
            return;
        }

        // /health is unauthenticated so external probes (Tailscale Funnel,
        // load balancers, smoke-test scripts) can verify reachability
        // without juggling tokens. It only reveals bridge readiness.
        if (url.pathname === '/health' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ status: 'ok', bridge: bridge.getStatus() }));
            return;
        }

        // Auth
        const auth = req.headers.authorization || '';
        const token = auth.replace(/^Bearer\s+/i, '');
        if (token !== authToken) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: { message: 'Unauthorized', type: 'auth_error' } }));
            return;
        }

        try {
            if (url.pathname === '/v1/chat/completions' && req.method === 'POST') {
                await handleChatCompletions(req, res, { bridge, config });
                return;
            }

            if (url.pathname === '/v1/models' && req.method === 'GET') {
                handleListModels(res, config);
                return;
            }

            res.writeHead(404, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: { message: 'Not found', type: 'not_found' } }));
        } catch (err) {
            logger.error(`HTTP API error: ${err.message}`);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: { message: err.message, type: 'server_error' } }));
        }
    });

    logger.info('HTTP API attached: /v1/chat/completions, /v1/models, /health');
}

function handleListModels(res, config) {
    const agents = config.listAgents();
    const data = agents.map(a => ({
        id: a.id,
        object: 'model',
        created: Math.floor(Date.now() / 1000),
        owned_by: 'openclaw-voice',
        name: a.name,
        description: a.description
    }));

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ object: 'list', data }));
}

async function handleChatCompletions(req, res, { bridge, config }) {
    const body = await readJsonBody(req);
    const { messages = [], stream = false, model } = body;

    // Extract the latest user message. ElevenLabs typically sends the full
    // conversation, but OpenClaw already maintains its own session state,
    // so we just forward the last user turn.
    const userMessage = [...messages].reverse().find(m => m.role === 'user');
    if (!userMessage?.content) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: 'No user message found', type: 'invalid_request' } }));
        return;
    }

    const text = typeof userMessage.content === 'string'
        ? userMessage.content
        : userMessage.content.map(c => c.text || '').join(' ');

    const commandId = uuid();
    logger.info(`[HTTP] /v1/chat/completions: "${text.substring(0, 80)}..." (model=${model || 'default'})`);

    if (stream) {
        await handleStreamingResponse(req, res, { bridge, text, commandId, model });
    } else {
        await handleNonStreamingResponse(res, { bridge, text, commandId, model });
    }
}

async function handleNonStreamingResponse(res, { bridge, text, commandId, model }) {
    let fullText = '';
    const finish = new Promise((resolve, reject) => {
        const onChunk = (data) => {
            if (data.commandId === commandId) {
                fullText += (fullText ? ' ' : '') + data.text;
            }
        };
        const onEnd = (data) => {
            if (data.commandId === commandId) {
                cleanup();
                resolve(data.fullText || fullText);
            }
        };
        const onError = (data) => {
            if (data.commandId === commandId) {
                cleanup();
                reject(new Error(data.message));
            }
        };
        const cleanup = () => {
            bridge.removeListener('response_chunk', onChunk);
            bridge.removeListener('response_end', onEnd);
            bridge.removeListener('response_error', onError);
        };
        bridge.on('response_chunk', onChunk);
        bridge.on('response_end', onEnd);
        bridge.on('response_error', onError);

        bridge.sendCommand(text, commandId).catch(err => {
            cleanup();
            reject(err);
        });

        // Safety timeout (matches OpenClaw's default 600s)
        setTimeout(() => { cleanup(); reject(new Error('Response timeout')); }, 120_000);
    });

    try {
        const responseText = await finish;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            id: `chatcmpl-${commandId}`,
            object: 'chat.completion',
            created: Math.floor(Date.now() / 1000),
            model: model || 'openclaw',
            choices: [{
                index: 0,
                message: { role: 'assistant', content: responseText },
                finish_reason: 'stop'
            }],
            usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
        }));
    } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: err.message, type: 'agent_error' } }));
    }
}

async function handleStreamingResponse(req, res, { bridge, text, commandId, model }) {
    res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive'
    });

    const createdAt = Math.floor(Date.now() / 1000);
    const completionId = `chatcmpl-${commandId}`;

    const writeChunk = (deltaText, finishReason = null) => {
        const payload = {
            id: completionId,
            object: 'chat.completion.chunk',
            created: createdAt,
            model: model || 'openclaw',
            choices: [{
                index: 0,
                delta: deltaText ? { content: deltaText } : {},
                finish_reason: finishReason
            }]
        };
        res.write(`data: ${JSON.stringify(payload)}\n\n`);
    };

    // First chunk: role
    res.write(`data: ${JSON.stringify({
        id: completionId,
        object: 'chat.completion.chunk',
        created: createdAt,
        model: model || 'openclaw',
        choices: [{ index: 0, delta: { role: 'assistant' }, finish_reason: null }]
    })}\n\n`);

    const done = new Promise((resolve, reject) => {
        const onChunk = (data) => {
            if (data.commandId === commandId) {
                writeChunk((data.text || '') + ' ');
            }
        };
        const onEnd = (data) => {
            if (data.commandId === commandId) {
                cleanup();
                writeChunk(null, 'stop');
                res.write('data: [DONE]\n\n');
                res.end();
                resolve();
            }
        };
        const onError = (data) => {
            if (data.commandId === commandId) {
                cleanup();
                writeChunk(null, 'stop');
                res.end();
                reject(new Error(data.message));
            }
        };
        const cleanup = () => {
            bridge.removeListener('response_chunk', onChunk);
            bridge.removeListener('response_end', onEnd);
            bridge.removeListener('response_error', onError);
        };
        bridge.on('response_chunk', onChunk);
        bridge.on('response_end', onEnd);
        bridge.on('response_error', onError);

        bridge.sendCommand(text, commandId).catch(err => {
            cleanup();
            writeChunk(null, 'stop');
            res.end();
            reject(err);
        });
    });

    try { await done; } catch (err) { logger.error(`Stream error: ${err.message}`); }
}

function readJsonBody(req) {
    return new Promise((resolve, reject) => {
        let body = '';
        req.on('data', (chunk) => body += chunk.toString());
        req.on('end', () => {
            try {
                resolve(body ? JSON.parse(body) : {});
            } catch (err) {
                reject(err);
            }
        });
        req.on('error', reject);
    });
}
