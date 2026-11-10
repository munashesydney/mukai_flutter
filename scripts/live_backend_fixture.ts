// Real Mukai backend with a local deterministic provider; disposable test data only.
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { startApiServer } from '../../mukai/src/server/app';
import type { Bot } from '../../mukai/src/shared/ai';

async function main() {
  const metadataFile = process.env.MUKAI_FIXTURE_METADATA;
  if (!metadataFile) throw new Error('Run this fixture with scripts/test_live_backend.py.');
  const root = await mkdtemp(join(tmpdir(), 'mukai-native-e2e-'));
  const webDir = join(root, 'web');
  const folder = join(root, 'workspace');
  await mkdir(webDir, { recursive: true });
  await mkdir(folder, { recursive: true });
  await writeFile(join(webDir, 'index.html'), '<html>Isolated Mukai simulator fixture</html>');
  await writeFile(join(folder, 'launch-notes.md'), '# A little launch\n\nOne clear outcome. Three good next steps.\n');
  await writeFile(join(folder, 'preview-image.webp'), await readFile(join(process.cwd(), '../mukai_flutter/assets/mascots/mukai-logo.webp')));
  let providerCalls = 0;
  const provider = createServer(async (request, response) => {
    try {
      const capture = /^\/capture\/([a-z0-9-]+)$/.exec(request.url || '');
      if (request.method === 'POST' && capture) {
        const directory = process.env.MUKAI_FIXTURE_CAPTURE_DIR;
        if (!directory) { response.writeHead(404).end(); return; }
        const chunks: Buffer[] = [];
        for await (const chunk of request) chunks.push(chunk);
        const png = Buffer.concat(chunks);
        if (png.length > 16 * 1024 * 1024 || png.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') {
          response.writeHead(400).end(); return;
        }
        await mkdir(directory, { recursive: true });
        const path = join(directory, `mukai-${capture[1]}.png`);
        await writeFile(path, png);
        console.log('MUKAI_VISUAL_CAPTURE:' + path);
        response.writeHead(204).end();
        return;
      }
      if (request.method === 'GET' && request.url === '/v1/models') {
        response.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({
          object: 'list', data: [{ id: 'mukai-fixture', object: 'model', owned_by: 'local-fixture' }],
        }));
        return;
      }
      if (request.method !== 'POST' || request.url !== '/v1/chat/completions') {
        response.writeHead(404).end();
        return;
      }
      const chunks: Buffer[] = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString());
      providerCalls++;
      appendFileSync(join(root, 'provider.log'), JSON.stringify({ at: new Date().toISOString(), call: providerCalls, model: body.model }) + '\n');
      const messages = body.messages || [];
      const userText = messages.filter((item: any) => item.role === 'user').map((item: any) =>
        typeof item.content === 'string' ? item.content : (item.content || []).map((part: any) => part.text || '').join('\n'));
      const prompt = userText.filter((text: string) => !text.trimStart().startsWith('[Mukai runtime')).at(-1) || '';
      const imageRequest = userText.some((text: string) => /view fixture image/i.test(text));
      const tools = (body.tools || []).map((item: any) => item.function?.name);
      // Mukai can append a user-role runtime reminder after tool results. Do
      // not mistake that reminder for a fresh turn and call the tool again.
      const calledTools = messages.flatMap((message: any) => message.tool_calls || [])
        .map((call: any) => call.function?.name);
      const toolFinished = messages.some((message: any) => message.role === 'tool');
      let toolName: string | undefined;
      let toolInput: unknown;
      if (tools.includes('report_pursuit') && !calledTools.includes('report_pursuit')) {
        toolName = 'report_pursuit';
        toolInput = {
          status: 'waiting', summary: 'Reviewed the launch plan. The next useful check is tomorrow.',
          nextRunAt: new Date(Date.now() + 86400000).toISOString(),
          nextRunReason: 'Give the launch checklist time to develop.',
          nextRunInstructions: 'Review launch-notes.md and update the checklist with the next useful step.',
        };
      } else if (tools.includes('media') && /view fixture image/i.test(prompt) && !calledTools.includes('media')) {
        toolName = 'media';
        toolInput = { action: 'view_image', path: 'preview-image.webp' };
      } else if (tools.includes('file_operations') && /write a note for approval/i.test(prompt) && !calledTools.includes('file_operations')) {
        toolName = 'file_operations';
        toolInput = { action: 'write_file', path: 'approval-fixture.md', content: '# A little momentum\nThis isolated file was approved from the native app.\n' };
      }
      console.log('MUKAI_FIXTURE_TOOL:' + JSON.stringify({ tools, toolName, prompt: prompt.slice(0, 100) }));
      const clockRequest = /Check workspace clock/i.test(prompt);
      const runtimeClock = userText.filter((text: string) => text.startsWith('[Mukai runtime context]')).at(-1) || '';
      const reply = clockRequest
        ? 'Clock received by provider:\n' + runtimeClock.split('\n').filter((line: string) => /^(Workspace timezone:|Workspace local now:|Runtime UTC now:)/.test(line)).join('\n')
        : imageRequest
        ? 'Here is the image from your workspace.\n\n![Mukai preview](preview-image.webp)\n\n[Launch notes](launch-notes.md#L2)'
        : toolFinished
        ? 'Done. Your workspace is up to date, and the result is saved for our next conversation.'
        : 'Live backend verified.\n\nHere is a little momentum for today:\n\n1. Choose one clear outcome.\n2. Make the first useful draft.\n3. Leave a note for what comes next.\n\nI am here when you are ready.';
      if (!body.stream) {
        response.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({
          id: randomUUID(), object: 'chat.completion', created: 1, model: body.model,
          choices: [{ index: 0, message: { role: 'assistant', content: reply }, finish_reason: 'stop' }],
          usage: { prompt_tokens: 100, completion_tokens: 40, total_tokens: 140 },
        }));
        return;
      }
      response.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
      const send = (delta: unknown, finish: string | null = null) => {
        if (response.destroyed) return;
        response.write(`data: ${JSON.stringify({
          id: 'fixture-' + providerCalls, object: 'chat.completion.chunk', created: 1, model: body.model,
          choices: [{ index: 0, delta, finish_reason: finish }],
        })}\n\n`);
      };
      if (toolName) {
        send({ tool_calls: [{ index: 0, id: randomUUID(), type: 'function', function: { name: toolName, arguments: JSON.stringify(toolInput) } }] });
        send({}, 'tool_calls');
      } else {
        const fragments = reply.match(/[\s\S]{1,22}/g) || [reply];
        // Delay fragments so the native app exercises actual streaming and Stop.
        for (let index = 0; index < fragments.length; index++) {
          if (response.destroyed) break;
          send({ content: fragments[index] });
          if (index === 0 && /slow explanation of the launch plan/i.test(prompt)) {
            await new Promise<void>((resolve) => {
              const timer = setTimeout(resolve, 30000);
              response.once('close', () => { clearTimeout(timer); resolve(); });
            });
          }
          await new Promise((resolve) => setTimeout(resolve, /slow/i.test(prompt) ? 700 : 90));
        }
        send({}, 'stop');
      }
      if (!response.destroyed) response.end('data: [DONE]\n\n');
    } catch {
      if (!response.headersSent) response.writeHead(500);
      response.end();
    }
  });
  await new Promise<void>((resolve) => provider.listen(0, '127.0.0.1', resolve));
  const providerUrl = `http://127.0.0.1:${(provider.address() as { port: number }).port}/v1`;
  const api = await startApiServer(0, {
    dataDir: join(root, 'data'), webDir, version: 'simulator-e2e',
    memoryExtractor: async () => ({ facts: [] }),
  });
  api.server.prependListener('request', (request) => {
    appendFileSync(join(root, 'requests.log'), JSON.stringify({
      at: new Date().toISOString(), method: request.method, path: request.url,
    }) + '\n');
  });
  // Claim the disposable instance exactly as a browser owner does. The native
  // app receives only these test credentials and obtains its own device session.
  const username = 'owner+native-fixture@example.com';
  const password = 'an isolated native owner passphrase';
  const proof = await fetch(api.url + '/api/auth/verify', {
    method: 'POST',
    headers: { Origin: api.url, 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: api.ownerAuth!.setupCode }),
  });
  if (!proof.ok) throw new Error(`Fixture owner proof failed (${proof.status}).`);
  const proofCookie = proof.headers.getSetCookie()[0]?.split(';')[0];
  if (!proofCookie) throw new Error('Fixture owner proof did not issue its browser cookie.');
  await proof.text();
  const owner = await fetch(api.url + '/api/auth/setup', {
    method: 'POST',
    headers: { Origin: api.url, Cookie: proofCookie, 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  if (!owner.ok) throw new Error(`Fixture owner setup failed (${owner.status}).`);
  await owner.text();
  const auth = { Authorization: `Bearer ${api.token}`, 'Content-Type': 'application/json' };
  async function call(path: string, method = 'GET', input?: unknown) {
    const response = await fetch(api.url + '/api' + path, {
      method, headers: auth,
      ...(input === undefined ? {} : { body: JSON.stringify(input) }),
    });
    const text = await response.text();
    if (!response.ok) throw new Error(`${method} ${path}: ${response.status} ${text}`);
    return text ? JSON.parse(text) : null;
  }
  const workspace = await call('/workspaces', 'POST', { name: 'A little launch', folder, timeZone: 'America/Vancouver' });
  const savedProvider = await call('/providers', 'POST', {
    name: 'Local simulator fixture', kind: 'compatible', baseUrl: providerUrl,
    defaultModel: 'mukai-fixture', models: [{ id: 'mukai-fixture', name: 'Mukai fixture', contextWindowTokens: 65536, maxOutputTokens: 4096, supportsImages: true }],
    supportsImages: true, isDefault: true, apiKey: 'isolated-local-fixture-key',
  });
  const bots: Bot[] = [];
  for (const [name, role, avatar] of [
    ['Scout', 'Your everyday orchestrator', 'scout'],
    ['Atlas', 'Build something worth keeping', 'atlas'],
    ['Nova', 'Research, writing, and fresh perspectives', 'nova'],
  ]) bots.push(await call('/bots', 'POST', {
    workspaceId: workspace.id, name, role, avatar,
    instructions: `You are ${name}, a helpful companion in an isolated simulator test.`,
    providerId: savedProvider.id, model: 'mukai-fixture', supportsImages: true,
  }));
  await call(`/tools/assignments?workspaceId=${workspace.id}`, 'PUT', { botId: bots[2].id, toolId: 'file_operations', enabled: true });
  await call(`/tools/assignments?workspaceId=${workspace.id}`, 'PUT', { botId: bots[2].id, toolId: 'media', enabled: true });
  const space = await call('/conversations', 'POST', {
    workspaceId: workspace.id, name: 'The launch room',
    description: 'A shared place for small ideas that move the launch forward.',
    botIds: bots.map((bot) => bot.id),
  });
  const pursuit = api.pursuits.create(bots[0], {
    name: 'Bring the launch to life',
    objective: 'Build a thoughtful launch checklist and keep the next useful step clear.\n\n' + 'Review what we learned, keep decisions in the Workpad, and choose one practical next step. '.repeat(65),
    successCriteria: 'A practical checklist is saved in the Workpad and the next review is scheduled.',
    firstRunAt: new Date(Date.now() + 86400000).toISOString(), deadline: null,
  });
  api.pursuits.addEntryOwned(bots[0], pursuit.id, {
    type: 'work_item', title: 'Make the first useful draft', content: 'Write three clear launch steps, then refine them together.', status: 'todo',
  });
  api.pursuits.addEntryOwned(bots[0], pursuit.id, {
    type: 'note', title: 'Keep it small and useful', content: 'One clear outcome is enough to start building momentum.',
  });
  // Seed a completed run through the real API, including its conversation.
  const historicalRun = await call(`/pursuits/${pursuit.id}/run`, 'POST');
  let completedRun;
  for (let attempt = 0; attempt < 400; attempt++) {
    completedRun = await call(`/pursuits/${pursuit.id}/run?runId=${historicalRun.id}`);
    if (completedRun.status !== 'running') break;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  if (completedRun?.status !== 'complete') throw new Error('The fixture pursuit run did not complete.');
  const completedMessages = await call(`/conversations/${completedRun.conversationId}/messages`);
  const source = [...completedMessages].reverse().find((m: any) => m.role === 'assistant');
  api.notifications.notify(bots[0], source.id, randomUUID(), {
    title: 'Your launch has a little momentum',
    message: '## A useful next step\n\nThe launch checklist is ready for review. Keep the next step small and useful.',
  });

  const conversation = await call(`/bots/${bots[2].id}/conversations`, 'POST');
  const seedStream = await fetch(`${api.url}/api/conversations/${conversation.id}/chat`, {
    method: 'POST', headers: { ...auth, Accept: 'text/event-stream' },
    body: JSON.stringify({ requestId: randomUUID(), text: 'Give me a little momentum for the launch.', attachmentIds: [] }),
  });
  const stream = await seedStream.text();
  if (!seedStream.ok || !stream.includes('"type":"done"')) throw new Error('Seed chat did not complete: ' + stream);
  await call('/instance');
  const meta = { baseUrl: api.url, username, password, root, pid: process.pid, workspaceId: workspace.id, bots: bots.map(({ id, name }) => ({ id, name })), conversationId: conversation.id, spaceId: space.id, pursuitId: pursuit.id, providerUrl, captureUrl: providerUrl.replace(/\/v1$/, '/capture') };
  await writeFile(metadataFile, JSON.stringify(meta, null, 2), { mode: 0o600 });
  console.log('Isolated native-app backend ready.');
  let closing = false;
  async function close() {
    if (closing) return;
    closing = true;
    await api.shutdown();
    await new Promise<void>((resolve) => api.server.close(() => resolve()));
    await new Promise<void>((resolve) => provider.close(() => resolve()));
    await rm(root, { recursive: true, force: true });
    await rm(metadataFile, { force: true });
    console.log('MUKAI_SIMULATOR_FIXTURE_CLEANED');
    process.exit(0);
  }
  process.on('SIGINT', () => void close());
  process.on('SIGTERM', () => void close());
}
main().catch((error) => { console.error(error); process.exit(1); });
