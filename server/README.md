# spottr-server

Node.js + TypeScript backend for Spottr. Mints OpenAI Realtime ephemeral keys
so the long-lived `OPENAI_API_KEY` never ships to the mobile app.

## Setup

```bash
cp .env.example .env
# edit .env and set OPENAI_API_KEY=sk-...
npm install
npm run dev
```

The server listens on `http://0.0.0.0:8787` by default. Make sure your phone
can reach the host on your LAN — set `EXPO_PUBLIC_BACKEND_URL` in `app/.env`
to your LAN IP, e.g. `http://192.168.1.10:8787`.

## Endpoints

### `GET /health`
Returns `{ ok: true, service: 'spottr-server' }`.

### `POST /api/realtime/session`
Body:
```json
{ "exercise": "squat" | "pushup", "targetReps": 10, "voice": "verse" }
```
Returns:
```json
{
  "sessionId": "sess_...",
  "clientSecret": "ek_...",
  "expiresAt": 1700000000,
  "model": "gpt-4o-realtime-preview-2024-12-17",
  "voice": "verse"
}
```

The mobile app uses `clientSecret` for the WebRTC handshake against
`https://api.openai.com/v1/realtime?model=...`.

## Notes

- Ephemeral keys expire in ~1 minute — the app fetches a new one each session.
- `coachInstructions` (in `src/prompts/coach.ts`) embeds Spottr's tone, allowed
  cues, and a strict "speak only when prompted" rule so the model doesn't
  monologue while the user is mid-rep.
