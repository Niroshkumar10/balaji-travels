'use strict';

/**
 * Disk storage for driver/vehicle KYC document uploads (license, ID proof,
 * driver photo, RC, insurance, permit, fitness, PUC — the document fields
 * added by vehicle_driver_documents.sql). Files land in server/uploads/kyc/
 * under a random name (never the client-supplied filename) and are served
 * back at GET /uploads/kyc/<name> — see app.js's static mount.
 *
 * Only the filename is stored in rt_drivers/rt_vehicles (…_doc_path columns),
 * matching what the existing document data in those columns already looks
 * like (bare filenames, no directory/URL prefix).
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const ApiError = require('../utils/apiError');

const UPLOAD_ROOT = path.join(__dirname, '..', '..', 'uploads');
const KYC_DIR = path.join(UPLOAD_ROOT, 'kyc');
fs.mkdirSync(KYC_DIR, { recursive: true });

const ALLOWED_EXT = new Set(['.jpg', '.jpeg', '.png', '.pdf', '.webp']);

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, KYC_DIR),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    cb(null, `${crypto.randomUUID()}${ALLOWED_EXT.has(ext) ? ext : ''}`);
  },
});

const fileFilter = (_req, file, cb) => {
  const ext = path.extname(file.originalname || '').toLowerCase();
  if (!ALLOWED_EXT.has(ext)) {
    cb(ApiError.badRequest('Only JPG, PNG, WEBP or PDF documents are accepted', 'INVALID_FILE_TYPE'));
    return;
  }
  cb(null, true);
};

const uploadDoc = multer({
  storage,
  fileFilter,
  limits: { fileSize: 8 * 1024 * 1024, files: 1 },
});

module.exports = { uploadDoc, UPLOAD_ROOT, KYC_DIR };
