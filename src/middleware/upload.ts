import multer from 'multer';
import path from 'path';
import fs from 'fs';
import crypto from 'node:crypto';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Upload security (P0):
 * - Public files (venue images, avatars, banners) live under public/uploads
 *   and remain served statically.
 * - Private files (KYC / identity / bank documents) live under
 *   private/uploads, which is NEVER served statically. Access is only via
 *   ownership-checked download endpoints.
 */

export const PUBLIC_UPLOAD_DIR = path.join(__dirname, '../../public/uploads');
export const PRIVATE_UPLOAD_DIR = path.join(__dirname, '../../private/uploads');

for (const dir of [PUBLIC_UPLOAD_DIR, PRIVATE_UPLOAD_DIR]) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

const ALLOWED_EXTENSIONS = new Set(['.jpeg', '.jpg', '.png', '.pdf']);
const ALLOWED_MIMETYPES = new Set(['image/jpeg', 'image/png', 'application/pdf']);
const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB

function storageFor(destination: string) {
  return multer.diskStorage({
    destination: (_req, _file, cb) => {
      cb(null, destination);
    },
    filename: (_req, file, cb) => {
      // Never trust the original filename: random name + validated extension.
      const ext = path.extname(file.originalname).toLowerCase();
      const safeExt = ALLOWED_EXTENSIONS.has(ext) ? ext : '';
      const random = crypto.randomBytes(16).toString('hex');
      cb(null, `upload-${Date.now()}-${random}${safeExt}`);
    },
  });
}

function fileFilter(_req: any, file: Express.Multer.File, cb: multer.FileFilterCallback) {
  // Block path traversal in the original name outright.
  const original = file.originalname || '';
  if (original.includes('/') || original.includes('\\') || original.includes('..')) {
    return cb(new Error('Invalid filename'));
  }
  const ext = path.extname(original).toLowerCase();
  // Block dangerous / executable types even if disguised (e.g. doc.php, img.jpg.exe).
  const lower = original.toLowerCase();
  if (/\.(php|exe|js|html|sh|bat|cmd|msi|dll|py|pl|cgi)\.?[^.]*$/i.test(lower)) {
    return cb(new Error('File type is not allowed'));
  }
  // Strict allowlist on BOTH extension and MIME. Notably,
  // application/octet-stream is NOT accepted (spoofable).
  if (ALLOWED_EXTENSIONS.has(ext) && ALLOWED_MIMETYPES.has(file.mimetype)) {
    return cb(null, true);
  }
  cb(new Error('Only JPEG, JPG, PNG, and PDF files are allowed!'));
}

/** Public uploads: venue images, avatars, banners. */
export const upload = multer({
  storage: storageFor(PUBLIC_UPLOAD_DIR),
  limits: { fileSize: MAX_FILE_SIZE },
  fileFilter,
});

/** Private uploads: KYC / identity / bank documents. Never served statically. */
export const uploadPrivate = multer({
  storage: storageFor(PRIVATE_UPLOAD_DIR),
  limits: { fileSize: MAX_FILE_SIZE },
  fileFilter,
});

/**
 * Validate actual file content (magic bytes) instead of trusting the
 * extension/MIME declared by the client. Deletes the file and throws when
 * the content does not match the claimed image/PDF type.
 */
export function validateUploadedFileContent(filePath: string, mimetype: string): void {
  const fd = fs.openSync(filePath, 'r');
  try {
    const header = Buffer.alloc(8);
    fs.readSync(fd, header, 0, 8, 0);
    let ok = false;
    if (mimetype === 'image/jpeg') {
      ok = header[0] === 0xff && header[1] === 0xd8;
    } else if (mimetype === 'image/png') {
      ok =
        header[0] === 0x89 &&
        header[1] === 0x50 &&
        header[2] === 0x4e &&
        header[3] === 0x47;
    } else if (mimetype === 'application/pdf') {
      ok = header.toString('ascii', 0, 5) === '%PDF-';
    }
    if (!ok) {
      try {
        fs.unlinkSync(filePath);
      } catch (_) {
        // ignore cleanup failure
      }
      throw new Error('File content does not match its declared type');
    }
  } finally {
    fs.closeSync(fd);
  }
}

/** Resolve a private file by bare filename; rejects traversal attempts. */
export function resolvePrivateFile(filename: string): string {
  const base = path.basename(filename);
  if (!base || base !== filename || base.includes('..')) {
    throw new Error('Invalid file reference');
  }
  return path.join(PRIVATE_UPLOAD_DIR, base);
}
