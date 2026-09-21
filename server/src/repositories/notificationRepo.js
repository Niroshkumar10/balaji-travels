'use strict';

const db = require('../infra/db');

const notificationRepo = {
  async create({ userId, type, title, body, data }, ctx = db) {
    const res = await ctx.query(
      `INSERT INTO rt_notifications (user_id, type, title, body, data)
       VALUES (:userId, :type, :title, :body, :data)`,
      { userId, type, title, body: body ?? null, data: data ? JSON.stringify(data) : null },
    );
    return res.insertId;
  },

  async list(userId, { limit = 30, offset = 0 } = {}, ctx = db) {
    return ctx.query(
      `SELECT id, type, title, body, data, read_at, created_at
         FROM rt_notifications WHERE user_id = :userId
        ORDER BY id DESC LIMIT :limit OFFSET :offset`,
      { userId, limit: Number(limit), offset: Number(offset) },
    );
  },

  async markRead(userId, id, ctx = db) {
    const res = await ctx.query(
      `UPDATE rt_notifications SET read_at = NOW()
        WHERE id = :id AND user_id = :userId AND read_at IS NULL`,
      { id, userId },
    );
    return res.affectedRows > 0;
  },

  async markAllRead(userId, ctx = db) {
    await ctx.query(
      `UPDATE rt_notifications SET read_at = NOW() WHERE user_id = :userId AND read_at IS NULL`,
      { userId },
    );
  },

  /** Has this user already been sent this notification type for this ride? */
  async existsForRide(userId, type, rideId, ctx = db) {
    const row = await ctx.queryOne(
      `SELECT id FROM rt_notifications
        WHERE user_id = :userId AND type = :type
          AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.rideId')) = :rideId
        LIMIT 1`,
      { userId, type, rideId: String(rideId) },
    );
    return !!row;
  },

  async unreadCount(userId, ctx = db) {
    const row = await ctx.queryOne(
      `SELECT COUNT(*) AS n FROM rt_notifications WHERE user_id = :userId AND read_at IS NULL`,
      { userId },
    );
    return Number(row?.n ?? 0);
  },
};

module.exports = notificationRepo;
