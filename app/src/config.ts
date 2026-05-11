export const BACKEND_URL =
  process.env.EXPO_PUBLIC_BACKEND_URL?.replace(/\/$/, '') ?? 'http://localhost:8787';

export const APP_VERSION = '0.1.0';
