'use strict';

const { Router } = require('express');
const { z } = require('zod');
const validate = require('../../middleware/validate');
const authenticate = require('../../middleware/auth');
const { otpLimiter } = require('../../middleware/rateLimit');
const asyncHandler = require('../../utils/asyncHandler');
const { mobile, loginRole, otpCode } = require('../../utils/validators');
const authController = require('../../controllers/authController');

const router = Router();

router.post(
  '/otp/request',
  otpLimiter,
  validate({ body: z.object({ mobile, role: loginRole }) }),
  asyncHandler(authController.requestOtp),
);

router.post(
  '/otp/verify',
  validate({ body: z.object({ mobile, role: loginRole, code: otpCode }) }),
  asyncHandler(authController.verifyOtp),
);

router.post('/logout', authenticate, asyncHandler(authController.logout));

router.post(
  '/fcm-token',
  authenticate,
  validate({ body: z.object({ fcmToken: z.string().min(10).max(512) }) }),
  asyncHandler(authController.registerFcmToken),
);

router.get('/me', authenticate, asyncHandler(authController.me));

module.exports = router;
