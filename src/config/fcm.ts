import { App, initializeApp, getApps, cert, deleteApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { AdminService } from '../modules/admin/admin.service.js';

let firebaseApp: App | null = null;
let currentConfigHash = "";

function calculateHash(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = (hash << 5) - hash + str.charCodeAt(i);
    hash |= 0;
  }
  return hash.toString();
}

export async function getFcmApp() {
  const settings = await AdminService.getSettings();
  if (!settings.useDynamicFcm || !settings.firebaseServiceAccount) {
    return null;
  }

  const configStr = settings.firebaseServiceAccount.trim();
  const configHash = calculateHash(configStr);

  if (firebaseApp && currentConfigHash === configHash) {
    return firebaseApp;
  }

  // Config changed or not initialized yet
  try {
    const serviceAccount = JSON.parse(configStr);

    // Delete existing app if initialized to allow hot-swapping
    if (firebaseApp) {
      await deleteApp(firebaseApp);
      firebaseApp = null;
    }

    // Find if app is already initialized in firebase admin namespace
    const existingApp = getApps().find(app => app?.name === '[DEFAULT]');
    if (existingApp) {
      await deleteApp(existingApp);
    }

    firebaseApp = initializeApp({
      credential: cert(serviceAccount)
    });
    currentConfigHash = configHash;
    console.log("Firebase Admin SDK dynamically initialized successfully!");
    return firebaseApp;
  } catch (err) {
    console.error("Failed to dynamically initialize Firebase Admin SDK:", err);
    return null;
  }
}

export async function sendPushNotification(token: string, title: string, body: string, data?: any): Promise<boolean> {
  try {
    const app = await getFcmApp();
    if (!app) return false;

    await getMessaging(app).send({
      token,
      notification: { title, body },
      data: data ? Object.keys(data).reduce((acc: any, key) => {
        acc[key] = String(data[key]);
        return acc;
      }, {}) : undefined
    });
    return true;
  } catch (err) {
    console.error("Error sending dynamic FCM push notification:", err);
    return false;
  }
}
