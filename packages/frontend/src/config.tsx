// Беремо адресу API з GitHub Actions, або використовуємо пряме посилання як запасний варіант
export const GATEWAY_URL = import.meta.env.VITE_API_URL || 'https://api.serhiigrin4-games.pp.ua';

export const MAX_FILE_SIZE = 500000;
export const FILES_BUCKET = import.meta.env.VITE_FILES_BUCKET;
export const REGION = import.meta.env.VITE_REGION;
export const IDENTITY_POOL_ID = import.meta.env.VITE_IDENTITY_POOL_ID;
export const BASE_URL = import.meta.env.BASE_URL;